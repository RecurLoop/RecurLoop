import { ChildProcessWithoutNullStreams, spawn } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as net from 'net';
import * as path from 'path';
import * as vscode from 'vscode';
import {
  hexDecode,
  expandWorkspaceVariables,
  likelyExecutableLine,
  libraryArguments,
  resolveExecutable,
  requireProject,
  rlString,
  stripAnsi,
  workspaceRoot
} from './util';

interface StopLocation {
  path: string;
  line: number;
  column: number;
  phrase: string;
  depth: number;
  threadId?: number;
  reason: 'breakpoint' | 'step' | 'pause' | 'entry' | 'exception';
}

interface RuntimeBreakpoint {
  id: number;
  path: string;
  line: number;
}

interface PendingInspection {
  stdout: string[];
  stderr: string[];
  resolve: (value: string) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
}

export class RecurLoopDebugAdapter implements vscode.DebugAdapter, vscode.Disposable {
  private readonly emitter = new vscode.EventEmitter<any>();
  public readonly onDidSendMessage = this.emitter.event;

  private requests: Promise<unknown> = Promise.resolve();
  private sequence = 1;
  private terminal?: vscode.Terminal;
  private terminalServer?: net.Server;
  private terminalSocket?: net.Socket;
  private terminalSocketPath?: string;
  private targetPid?: number;
  private readonly nativeFrames = new Map<number, { thread: number; frame: number }>();
  private readonly nativeVariables = new Map<number, { thread: number; frame: number; path: string }>();
  private nextFrame = 2;
  private nextVariable = 1000000;
  private initialStop = true;
  private entryPending = false;
  private resumeAfterBreakpointUpdate = false;
  private readonly sourceTerminalWrite = new vscode.EventEmitter<string>();
  private commandQueue: Promise<unknown> = Promise.resolve();
  private functionBreakpoints: string[] = [];
  private functionBreakpointOptions: any[] = [];
  private readonly breakpointOptions = new Map<string, any[]>();
  private nextBreakpointId = 1;
  private readonly hitCounts = new Map<string, number>();
  private configuration: any;
  private child?: ChildProcessWithoutNullStreams;
  private controllerPath?: string;
  private stdoutBuffer = '';
  private stopped?: StopLocation;
  private pendingStop?: StopLocation;
  private finalizingStop = false;
  private atPrompt = false;
  private terminated = false;
  private breakpointDirty = false;
  private readonly breakpoints = new Map<string, number[]>();
  private runtimeBreakpoints: RuntimeBreakpoint[] = [];
  private pendingInspection?: PendingInspection;

  constructor(private readonly output: vscode.OutputChannel) {}

  public handleMessage(message: any): void {
    if (message?.type !== 'request') return;
    this.requests = this.requests.then(() => this.dispatch(message)).catch(error => {
      this.sendError(message, error instanceof Error ? error.message : String(error));
    });
  }

  private async dispatch(request: any): Promise<void> {
    switch (request.command) {
      case 'initialize':
        this.sendResponse(request, {
          supportsConfigurationDoneRequest: true,
          supportsEvaluateForHovers: true,
          supportsTerminateRequest: true,
          supportsRestartRequest: true,
          supportsSetVariable: true,
          supportsFunctionBreakpoints: true,
          supportsConditionalBreakpoints: true,
          supportsHitConditionalBreakpoints: true,
          supportsLogPoints: true
        });
        return;
      case 'launch':
        this.configuration = request.arguments ?? {};
        this.sendResponse(request);
        this.sendEvent('initialized');
        return;
      case 'setBreakpoints':
        await this.setBreakpoints(request);
        return;
      case 'setFunctionBreakpoints':
        this.functionBreakpointOptions = request.arguments?.breakpoints ?? [];
        this.functionBreakpoints = this.functionBreakpointOptions.map(item => String(item.name));
        for (const key of this.hitCounts.keys()) if (key.startsWith('function:')) this.hitCounts.delete(key);
        this.breakpointDirty = Boolean(this.child);
        this.pauseForBreakpointUpdate();
        if (this.stopped && this.atPrompt) await this.applyLiveBreakpoints();
        this.sendResponse(request, { breakpoints: this.functionBreakpoints.map(() => ({ verified: true })) });
        return;
      case 'setVariable': {
        const scope = this.nativeScope(Number(request.arguments?.variablesReference ?? 1));
        await this.selectFrame(scope.frame, scope.thread);
        const name = String(request.arguments.name).replace(/[\r\n]/g, '');
        const variable = scope.path ? scope.path + (name.startsWith('[') ? '' : '.') + name : name;
        const response = await this.sendInspectionCommand(`set ${variable} = ${String(request.arguments.value).replace(/[\r\n]/g, '')}`);
        const value = response.match(/\[debug\] (.+):([^ ]+) = (.*)/);
        if (!value) throw new Error(response || 'Cannot update variable');
        this.sendResponse(request, { value: value[3], type: value[2], variablesReference: 0 });
        return;
      }
      case 'setExceptionBreakpoints':
        this.sendResponse(request, { breakpoints: [] });
        return;
      case 'configurationDone':
        await this.start();
        this.sendResponse(request);
        return;
      case 'threads': {
        if (!this.configuration?.executable || !this.stopped || !this.atPrompt) {
          this.sendResponse(request, { threads: [{ id: this.stopped?.threadId ?? this.targetPid ?? 1, name: 'RecurLoop' }] });
          return;
        }
        const response = await this.sendInspectionCommand('threads');
        const threads = response.split('\n').filter(line => line.startsWith('[debug-thread]\t')).map(line => {
          const fields = line.split('\t');
          return { id: Number(fields[1]), name: `${hexDecode(fields[2]) || 'RecurLoop'} (${fields[1]})` };
        });
        this.sendResponse(request, { threads });
        return;
      }
      case 'stackTrace':
        await this.stackTrace(request);
        return;
      case 'scopes':
        this.sendResponse(request, {
          scopes: [{ name: 'Local variables', variablesReference: Number(request.arguments?.frameId ?? 1), expensive: false }]
        });
        return;
      case 'variables':
        await this.variables(request);
        return;
      case 'evaluate':
        await this.evaluate(request);
        return;
      case 'continue':
        await this.control(request, 'continue');
        return;
      case 'next':
        await this.control(request, 'next');
        return;
      case 'stepIn':
        await this.control(request, 'step');
        return;
      case 'stepOut':
        await this.control(request, 'finish');
        return;
      case 'pause':
        if (!this.targetPid) throw new Error('Pause requires an emitted executable target.');
        if (this.child?.pid) process.kill(this.child.pid, 'SIGUSR1');
        this.sendResponse(request);
        return;
      case 'restart':
        this.stop(false);
        this.stdoutBuffer = '';
        await this.start();
        this.sendResponse(request);
        return;
      case 'disconnect':
      case 'terminate':
        this.sendResponse(request);
        this.stop(true);
        return;
      default:
        this.sendResponse(request);
    }
  }

  private async setBreakpoints(request: any): Promise<void> {
    const sourcePath = request.arguments?.source?.path as string | undefined;
    if (!sourcePath) {
      this.sendResponse(request, { breakpoints: [] });
      return;
    }
    const requested: number[] = (request.arguments?.breakpoints ?? []).map((item: any) => Number(item.line)).filter((line: number) => line > 0);
    let source = '';
    try { source = fs.readFileSync(sourcePath, 'utf8'); } catch { /* unsaved/non-local file */ }
    const resolved = requested.map(line => source ? likelyExecutableLine(source, line) : line);
    for (const key of this.hitCounts.keys()) if (key.startsWith(`${path.resolve(sourcePath)}:`)) this.hitCounts.delete(key);
    this.breakpoints.set(path.resolve(sourcePath), resolved);
    this.breakpointOptions.set(path.resolve(sourcePath), (request.arguments?.breakpoints ?? []).map((item: any, index: number) => ({ ...item, line: resolved[index], id: this.nextBreakpointId++, verified: !this.configuration?.executable })));
    this.breakpointDirty = Boolean(this.child);
    this.pauseForBreakpointUpdate();

    if (this.child && this.stopped && this.atPrompt) {
      await this.applyLiveBreakpoints();
    }

    this.sendResponse(request, {
      breakpoints: resolved.map((line, index) => ({
        id: this.breakpointOptions.get(path.resolve(sourcePath))?.[index]?.id,
        verified: this.breakpointOptions.get(path.resolve(sourcePath))?.[index]?.verified ?? true,
        line: this.breakpointOptions.get(path.resolve(sourcePath))?.[index]?.actualLine ?? line,
        source: request.arguments.source,
        message: line !== requested[index] ? `Resolved from line ${requested[index]} to the next likely executable line.` : undefined
      }))
    });
  }

  private async stackTrace(request: any): Promise<void> {
    if (!this.stopped) {
      this.sendResponse(request, { stackFrames: [], totalFrames: 0 });
      return;
    }
    if (this.configuration.executable) {
      const thread = Number(request.arguments?.threadId ?? this.stopped.threadId ?? this.targetPid);
      await this.sendInspectionCommand(`thread ${thread}`);
      const response = await this.sendInspectionCommand('stack');
      const frames = response.split('\n').filter(line => line.startsWith('[debug-frame]\t')).map(line => {
        const fields = line.split('\t');
        const file = hexDecode(fields[2]);
        return { id: this.frameHandle(thread, Number(fields[1])), name: hexDecode(fields[5]) || '<recurloop>',
          ...(file.startsWith('<') ? { presentationHint: 'subtle' } : { source: { name: path.basename(file), path: file } }),
          line: Number(fields[3]), column: Number(fields[4]) };
      });
      const start = Number(request.arguments?.startFrame ?? 0);
      const count = Number(request.arguments?.levels ?? frames.length);
      this.sendResponse(request, { stackFrames: frames.slice(start, count ? start + count : undefined), totalFrames: frames.length });
      return;
    }
    const source: any = { name: path.basename(this.stopped.path), path: this.stopped.path };
    this.sendResponse(request, {
      stackFrames: [{
        id: 1,
        name: this.stopped.phrase || '<recurloop>',
        source,
        line: this.stopped.line,
        column: this.stopped.column
      }],
      totalFrames: 1
    });
  }

  private async variables(request: any): Promise<void> {
    if (!this.stopped || !this.atPrompt) {
      this.sendResponse(request, { variables: [] });
      return;
    }
    if (this.configuration.executable) {
      const scope = this.nativeScope(Number(request.arguments?.variablesReference ?? 1));
      await this.selectFrame(scope.frame, scope.thread);
      const start = Math.max(0, Number(request.arguments?.start ?? 0));
      const count = Math.min(1024, Math.max(0, Number(request.arguments?.count ?? 100)));
      const response = await this.sendInspectionCommand(scope.path
        ? `children ${rlString(scope.path)}, ${start}, ${count}` : 'locals');
      const variables = this.parseNativeVariables(response, scope.thread, scope.frame);
      this.sendResponse(request, { variables });
      return;
    }
    const candidates = this.variableCandidates(this.stopped.path, this.stopped.line);
    const variables: any[] = [];
    for (const name of candidates.slice(-24).reverse()) {
      try {
        const result = await this.evaluateExpression(name);
        if (result) variables.push({ name, value: result.value, type: result.type, variablesReference: 0 });
      } catch {
        // A lexical candidate can be out of scope at the current debugger event.
      }
    }
    this.sendResponse(request, { variables });
  }

  private async evaluate(request: any): Promise<void> {
    const expression = String(request.arguments?.expression ?? '').trim();
    if (!expression) {
      this.sendResponse(request, { result: '', variablesReference: 0 });
      return;
    }
    if (!this.stopped || !this.atPrompt) {
      this.sendError(request, 'RecurLoop expressions can be evaluated only while the target is stopped.');
      return;
    }
    const scope = this.nativeScope(Number(request.arguments?.frameId ?? 1));
    await this.selectFrame(scope.frame, scope.thread);
    if (this.configuration.executable && /^[A-Za-z_]\w*(?:(?:\.|->)[A-Za-z_]\w*|\[\d+\])*$/.test(expression)) {
      const response = await this.sendInspectionCommand(`value ${rlString(expression)}`);
      const variable = this.parseNativeVariables(response, scope.thread, scope.frame)[0];
      if (!variable) throw new Error(`Could not inspect '${expression}'.`);
      this.sendResponse(request, { result: variable.value, type: variable.type,
        variablesReference: variable.variablesReference, namedVariables: variable.namedVariables,
        indexedVariables: variable.indexedVariables });
      return;
    }
    const result = await this.evaluateExpression(expression);
    if (!result) {
      this.sendError(request, `Could not evaluate '${expression}'.`);
      return;
    }
    this.sendResponse(request, { result: result.value, type: result.type, variablesReference: 0 });
  }

  private async control(request: any, command: 'continue' | 'next' | 'step' | 'finish'): Promise<void> {
    if (!this.child || !this.stopped || !this.atPrompt) {
      this.sendError(request, 'RecurLoop target is not stopped.');
      return;
    }
    const threadId = Number(request.arguments?.threadId ?? this.stopped.threadId ?? this.targetPid ?? 1);
    if (this.configuration.executable) await this.sendInspectionCommand(`thread ${threadId}`);
    this.stopped = undefined;
    this.pendingStop = undefined;
    this.atPrompt = false;
    this.child.stdin.write(command + '\n');
    this.sendResponse(request, command === 'continue' ? { allThreadsContinued: true } : undefined);
    this.sendEvent('continued', { threadId, allThreadsContinued: command === 'continue' });
  }

  private async start(): Promise<void> {
    if (this.child) return;
    const rawProgram = String(this.configuration?.executable ?? this.configuration?.program ?? '');
    if (!rawProgram) throw new Error('RecurLoop debug configuration requires "program" or "executable".');
    const workspaceUri = (this.configuration.cwd
      ? vscode.workspace.getWorkspaceFolder(vscode.Uri.file(this.configuration.cwd))?.uri : undefined)
      ?? vscode.workspace.workspaceFolders?.[0]?.uri;
    requireProject(workspaceUri);
    const program = path.resolve(expandWorkspaceVariables(rawProgram, workspaceUri));
    const cwd = path.resolve(expandWorkspaceVariables(String(this.configuration?.cwd ?? workspaceRoot(workspaceUri)), workspaceUri));
    const executable = resolveExecutable(workspaceUri, this.configuration?.recurloop);
    if (!fs.existsSync(program)) throw new Error(`RecurLoop debug program does not exist: ${program}`);

    const configured = this.allBreakpoints();
    if (this.configuration?.stopOnEntry && !this.configuration.executable) {
      const source = fs.readFileSync(program, 'utf8');
      configured.unshift({ path: program, line: likelyExecutableLine(source, 1) });
    }

    const tty = this.configuration.executable ? await this.openTerminal(cwd) : undefined;
    this.initialStop = true;
    this.entryPending = Boolean(this.configuration.stopOnEntry);
    this.resumeAfterBreakpointUpdate = false;
    if (!this.configuration.executable) {
      this.terminal = vscode.window.createTerminal({ name: 'RecurLoop: source program', pty: {
        onDidWrite: this.sourceTerminalWrite.event, open: () => {}, close: () => this.stop(true),
        handleInput: (text: string) => { if (!this.stopped) this.child?.stdin.write(text); } } });
      this.terminal.show(true);
    }
    this.hitCounts.clear();
    const controller = [
      '// Generated by the RecurLoop VS Code debug adapter.',
      ...(!this.configuration.executable && this.configuration?.projectFile ? [`include ${rlString(this.configuration.projectFile)}`] : []),
      'debug:trace off',
      ...(tty ? [`debug:terminal ${rlString(tty)}`] : []),
      ...this.functionBreakpoints.map(name => `debug:break function ${rlString(name)}`),
      ...configured.map(item => `debug:break line ${rlString(item.path)}:${item.line}`),
      `debug:${this.configuration.executable ? 'executable run' : 'run'} ${rlString(program)}`,
      ''
    ].join('\n');
    this.controllerPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'rl-debug-controller-')), 'main.rl');
    fs.writeFileSync(this.controllerPath, controller, { encoding: 'utf8', mode: 0o600 });
    this.runtimeBreakpoints = configured.map((item, index) => ({ id: this.functionBreakpoints.length + index + 1, ...item }));
    this.breakpointDirty = false;
    this.terminated = false;

    this.output.appendLine(`[debug] ${executable} --file ${this.controllerPath}`);
    const child = spawn(executable, [...libraryArguments(workspaceUri), '--file', this.controllerPath], {
      cwd,
      env: { ...process.env, NO_COLOR: '1' },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    this.child = child;
    child.stdout.on('data', chunk => this.onStdout(chunk.toString('utf8')));
    child.stderr.on('data', chunk => this.onStderr(chunk.toString('utf8')));
    child.on('error', error => {
      this.sendEvent('output', { category: 'stderr', output: `[adapter] ${error.message}\n` });
    });
    child.on('exit', (code, signal) => {
      if (this.child !== child) return;
      this.sendEvent('output', { category: 'console', output: `[adapter] RecurLoop exited code=${code ?? '-'} signal=${signal ?? '-'}\n` });
      this.child = undefined;
      this.atPrompt = false;
      this.stopped = undefined;
      this.rejectInspection(new Error('RecurLoop debug process exited.'));
      this.cleanupController();
      this.closeTerminal();
      if (!this.terminated) {
        this.terminated = true;
        this.sendEvent('terminated');
      }
    });
  }

  private onStdout(text: string): void {
    this.stdoutBuffer += text;
    while (this.stdoutBuffer.length) {
      const newline = this.stdoutBuffer.indexOf('\n');
      const prompt = this.stdoutBuffer.indexOf('debug> ');
      if (prompt >= 0 && (newline < 0 || prompt < newline)) {
        const prefix = this.stdoutBuffer.slice(0, prompt);
        if (prefix) this.handleLine(prefix);
        this.stdoutBuffer = this.stdoutBuffer.slice(prompt + 'debug> '.length);
        this.handlePrompt();
        continue;
      }
      if (newline >= 0) {
        const line = this.stdoutBuffer.slice(0, newline).replace(/\r$/, '');
        this.stdoutBuffer = this.stdoutBuffer.slice(newline + 1);
        this.handleLine(line);
        continue;
      }
      break;
    }
  }

  private onStderr(text: string): void {
    const clean = stripAnsi(text);
    if (this.pendingInspection) this.pendingInspection.stderr.push(clean);
    this.sendEvent('output', { category: 'stderr', output: clean });
  }

  private handleLine(rawLine: string): void {
    const line = stripAnsi(rawLine);
    if (this.pendingInspection) this.pendingInspection.stdout.push(line);
    if (line && !/^\[debug-(?:event|frame|variable|thread)\]/.test(line)) {
      if (!this.configuration.executable && !line.startsWith('[debug]')) this.sourceTerminalWrite.fire(line + '\r\n');
      else this.sendEvent('output', { category: 'console', output: line + '\n' });
    }

    const pid = line.match(/^\[debug\] executable started pid (\d+)/);
    if (pid) { this.targetPid = Number(pid[1]); this.breakpointDirty = true; }
    if (line.startsWith('[debug-event]\tstop\t')) {
      const fields = line.split('\t');
      this.pendingStop = { reason: fields[2] === 'breakpoint' ? 'breakpoint' : fields[2] === 'signal' ? 'exception' : fields[2] === 'paused' ? 'pause' : 'step',
        path: hexDecode(fields[3]), line: Number(fields[4]), column: Number(fields[5]),
        phrase: hexDecode(fields[7]) || hexDecode(fields[6]), depth: 0, threadId: Number(fields[8]) || this.targetPid };
      return;
    }
    const stop = line.match(/^\[debug\] (breakpoint|stopped) (.+):(\d+):(\d+) phrase "(.*)" depth (\d+)$/);
    if (stop) {
      this.pendingStop = {
        reason: stop[1] === 'breakpoint' ? 'breakpoint' : 'step',
        path: stop[2],
        line: Number.parseInt(stop[3], 10),
        column: Number.parseInt(stop[4], 10),
        phrase: stop[5],
        depth: Number.parseInt(stop[6], 10)
      };
    }
  }

  private handlePrompt(): void {
    this.atPrompt = true;
    const pending = this.pendingInspection;
    if (pending) {
      this.pendingInspection = undefined;
      clearTimeout(pending.timer);
      const combined = [...pending.stdout, ...pending.stderr].join('\n').trim();
      if (/^(?:.*:\d+:\d+:|Exception:)/m.test(combined)) pending.reject(new Error(combined));
      else pending.resolve(combined);
    }
    if (this.pendingStop && !this.finalizingStop) void this.finalizeStop();
  }

  private async finalizeStop(): Promise<void> {
    if (!this.pendingStop) return;
    this.finalizingStop = true;
    try {
      if (this.breakpointDirty) await this.applyLiveBreakpoints();
      this.stopped = this.pendingStop;
      this.pendingStop = undefined;
      this.nativeFrames.clear(); this.nativeVariables.clear(); this.nextFrame = 2; this.nextVariable = 1000000;
      this.nativeFrames.set(1, { thread: this.stopped.threadId ?? this.targetPid ?? 1, frame: 0 });
      if (this.resumeAfterBreakpointUpdate) {
        this.resumeAfterBreakpointUpdate = false;
        this.stopped = undefined;
        this.atPrompt = false;
        this.child?.stdin.write('continue\n');
        return;
      }
      if (this.configuration.executable && this.initialStop) {
        this.initialStop = false;
        this.atPrompt = false;
        this.stopped = undefined;
        this.child?.stdin.write(this.configuration.stopOnEntry ? 'step\n' : 'continue\n');
        return;
      }
      if (this.entryPending) {
        if (!this.stopped.path || this.stopped.path.startsWith('<')) {
          this.stopped = undefined; this.atPrompt = false; this.child?.stdin.write('step\n'); return;
        }
        this.entryPending = false;
        this.stopped.reason = 'entry';
      }
      if (this.stopped.reason === 'breakpoint' && !(await this.acceptBreakpoint(this.stopped))) {
        this.stopped = undefined;
        this.atPrompt = false;
        this.child?.stdin.write('continue\n');
        return;
      }
      if (!this.stopped.path && this.stopped.reason !== 'exception') this.stopped.reason = 'pause';
      this.sendEvent('stopped', { reason: this.stopped.reason, threadId: this.stopped.threadId ?? 1, allThreadsStopped: true });
    } catch (error) {
      this.sendEvent('output', { category: 'stderr', output: `[debug] ${String(error)}\n` });
      this.pendingStop = undefined;
      if (this.stopped) this.sendEvent('stopped', { reason: 'breakpoint', threadId: this.stopped.threadId ?? 1, allThreadsStopped: true });
    } finally {
      this.finalizingStop = false;
    }
  }

  private pauseForBreakpointUpdate(): void {
    if (this.configuration?.executable && this.targetPid && !this.stopped && !this.pendingStop && !this.atPrompt) {
      this.resumeAfterBreakpointUpdate = true;
      if (this.child?.pid) process.kill(this.child.pid, 'SIGUSR1');
    }
  }

  private async applyLiveBreakpoints(): Promise<void> {
    if (!this.child || !this.atPrompt) return;
    for (const breakpoint of this.runtimeBreakpoints) {
      try { await this.sendInspectionCommand(`delete ${breakpoint.id}`); } catch { /* already absent */ }
    }
    this.runtimeBreakpoints = [];
    const listed = await this.sendInspectionCommand('breakpoints');
    // Function breakpoints share the host's id space with source breakpoints.
    for (const line of listed.split('\n')) {
      const id = line.match(/^\[debug\] (\d+) /);
      if (id) await this.sendInspectionCommand(`delete ${id[1]}`);
    }
    for (const name of this.functionBreakpoints) await this.sendInspectionCommand(`break function ${rlString(name)}`);
    for (const item of this.allBreakpoints()) {
      const response = await this.sendInspectionCommand(`break line ${rlString(item.path)}:${item.line}`);
      const match = response.match(/\[debug\] breakpoint (\d+)/);
      if (match) this.runtimeBreakpoints.push({ id: Number.parseInt(match[1], 10), ...item });
      const resolved = response.match(/ resolved .*:(\d+)$/m);
      for (const option of this.breakpointOptions.get(item.path) ?? []) {
        if (option.line !== item.line) continue;
        option.actualLine = resolved ? Number(resolved[1]) : item.line;
        option.verified = !response.includes(' unresolved');
        this.sendEvent('breakpoint', { reason: 'changed', breakpoint: { id: option.id,
          verified: option.verified, line: option.actualLine, source: { path: item.path },
          message: option.verified ? undefined : 'No emitted statement in this source at or after the requested line.' } });
      }
    }
    this.breakpointDirty = false;
  }

  private async evaluateExpression(expression: string): Promise<{ type: string; value: string } | undefined> {
    const safe = expression.replace(/[\r\n]+/g, ' ');
    const response = await this.sendInspectionCommand(`eval ${safe}`);
    const lines = response.split(/\r?\n/).map(stripAnsi);
    for (let index = lines.length - 1; index >= 0; --index) {
      const match = lines[index].match(/^\[debug\]\s+(\S+)\s+(.*)$/);
      if (!match) continue;
      if (/requires|does not|unknown|cannot|invalid|failed/i.test(lines[index])) return undefined;
      return { type: match[1], value: match[2] };
    }
    return undefined;
  }

  private nativeScope(reference: number): { thread: number; frame: number; path?: string } {
    return this.nativeVariables.get(reference) ?? this.nativeFrames.get(reference)
      ?? { thread: this.stopped?.threadId ?? this.targetPid ?? 1, frame: Math.max(0, reference - 1) };
  }

  private frameHandle(thread: number, frame: number): number {
    for (const [id, scope] of this.nativeFrames) if (scope.thread === thread && scope.frame === frame) return id;
    const id = this.nextFrame++; this.nativeFrames.set(id, { thread, frame }); return id;
  }

  private parseNativeVariables(response: string, thread: number, frame: number): any[] {
    return response.split('\n').filter(line => line.startsWith('[debug-variable]\t')).map(line => {
      const fields = line.split('\t');
      const variablePath = hexDecode(fields[1]);
      const children = Number(fields[5]);
      let reference = 0;
      if (children) {
        reference = this.nextVariable++;
        this.nativeVariables.set(reference, { thread, frame, path: variablePath });
      }
      return { name: hexDecode(fields[2]), type: hexDecode(fields[3]), value: hexDecode(fields[4]),
        evaluateName: variablePath, variablesReference: reference,
        ...(Number(fields[6]) === 4 ? { indexedVariables: children } : { namedVariables: children }) };
    });
  }

  private async selectFrame(frame: number, thread = this.stopped?.threadId ?? this.targetPid ?? 1): Promise<void> {
    if (!this.configuration.executable) return;
    await this.sendInspectionCommand(`thread ${thread}`);
    await this.sendInspectionCommand(`frame ${frame}`);
  }

  private sendInspectionCommand(command: string): Promise<string> {
    const operation = this.commandQueue.then(() => this.inspectionCommand(command));
    this.commandQueue = operation.catch(() => undefined);
    return operation;
  }

  private inspectionCommand(command: string): Promise<string> {
    if (!this.child || !this.atPrompt || this.pendingInspection) return Promise.reject(new Error('Debugger controller is busy.'));
    this.atPrompt = false;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pendingInspection) this.pendingInspection = undefined;
        reject(new Error(`Debugger command timed out: ${command}`));
      }, 2500);
      this.pendingInspection = { stdout: [], stderr: [], resolve, reject, timer };
      this.child!.stdin.write(command + '\n');
    });
  }

  private rejectInspection(error: Error): void {
    const pending = this.pendingInspection;
    if (!pending) return;
    this.pendingInspection = undefined;
    clearTimeout(pending.timer);
    pending.reject(error);
  }

  private async acceptBreakpoint(stop: StopLocation): Promise<boolean> {
    const options = this.breakpointOptions.get(path.resolve(stop.path))?.find(item => (item.actualLine ?? item.line) === stop.line)
      ?? this.functionBreakpointOptions.find(item => item.name === stop.phrase);
    if (!options) return true;
    const key = options.name ? `function:${options.name}` : `${stop.path}:${stop.line}`;
    const count = (this.hitCounts.get(key) ?? 0) + 1;
    this.hitCounts.set(key, count);
    if (options.hitCondition) {
      const condition = String(options.hitCondition).trim();
      const match = condition.match(/^(?:(>=|>|==|%)\s*)?(\d+)$/);
      if (!match) throw new Error('Hit condition must be a count, >= N, > N, == N or % N.');
      const value = Number(match[2]);
      if (!(match[1] === '>=' ? count >= value : match[1] === '>' ? count > value : match[1] === '%' ? value > 0 && count % value === 0 : count === value)) return false;
    }
    if (options.condition) {
      await this.selectFrame(0);
      const result = await this.evaluateExpression(String(options.condition));
      if (!result || result.value === 'false' || result.value === '0') return false;
    }
    if (options.logMessage) {
      let message = String(options.logMessage);
      for (const match of [...message.matchAll(/\{([^}]+)\}/g)]) {
        const result = await this.evaluateExpression(match[1]);
        message = message.replace(match[0], result?.value ?? '<unavailable>');
      }
      this.sendEvent('output', { category: 'console', output: message + '\n' });
      return false;
    }
    return true;
  }

  private async openTerminal(cwd: string): Promise<string> {
    this.terminalSocketPath = path.join(os.tmpdir(), `rl-debug-tty-${process.pid}-${Math.random().toString(16).slice(2)}.sock`);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.closeTerminal(); reject(new Error('Debug terminal did not start within 10 seconds.')); }, 10000);
      this.terminalServer = net.createServer(socket => {
        if (this.terminalSocket) { socket.destroy(); return; }
        this.terminalSocket = socket;
        let buffer = '';
        socket.on('data', chunk => {
          buffer += chunk.toString();
          while (buffer.includes('\n')) {
            const end = buffer.indexOf('\n');
            const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
            if (line.startsWith('/dev/pts/')) { clearTimeout(timer); resolve(line); }
            else if (line === 'interrupt' && this.child?.pid) process.kill(this.child.pid, 'SIGUSR1');
          }
        });
        socket.on('close', () => {
          if (this.terminalSocket === socket && this.child) this.stop(true);
        });
        socket.on('error', error => this.output.appendLine(`[debug terminal] ${error.message}`));
      });
      this.terminalServer.once('error', error => { clearTimeout(timer); reject(error); });
      this.terminalServer.listen(this.terminalSocketPath, () => {
        fs.chmodSync(this.terminalSocketPath!, 0o600);
        this.terminal = vscode.window.createTerminal({ name: 'RecurLoop: application', cwd,
          shellPath: process.execPath,
          shellArgs: [path.resolve(__dirname, '../resources/debug-terminal.js'), this.terminalSocketPath!],
          env: { ELECTRON_RUN_AS_NODE: '1' } });
        this.terminal.show(true);
      });
    });
  }

  private closeTerminal(): void {
    this.targetPid = undefined;
    this.terminalSocket?.end(); this.terminalSocket = undefined;
    this.terminalServer?.close(); this.terminalServer = undefined;
    if (this.terminalSocketPath) { try { fs.unlinkSync(this.terminalSocketPath); } catch { /* removed */ } }
    this.terminalSocketPath = undefined;
    // Leave completed application output available in the terminal panel.
    this.terminal = undefined;
  }

  private variableCandidates(file: string, line: number): string[] {
    let source: string;
    try { source = fs.readFileSync(file, 'utf8').split(/\r?\n/).slice(0, line).join('\n'); } catch { return []; }
    const names: string[] = [];
    const seen = new Set<string>();
    const add = (name: string) => {
      if (!name || seen.has(name)) return;
      seen.add(name);
      names.push(name);
    };
    for (const match of source.matchAll(/\b(?:let|var|const)\s+([A-Za-z_][A-Za-z0-9_:]*)/g)) add(match[1]);
    for (const fn of source.matchAll(/\bfn(?:\s+[A-Za-z_][A-Za-z0-9_:]*)?\s*\(([^)]*)\)/g)) {
      for (const parameter of fn[1].matchAll(/([A-Za-z_][A-Za-z0-9_]*)\s*:/g)) add(parameter[1]);
    }
    return names;
  }

  private allBreakpoints(): Array<{ path: string; line: number }> {
    const result: Array<{ path: string; line: number }> = [];
    for (const [file, lines] of [...this.breakpoints.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      for (const line of [...new Set(lines)].sort((a, b) => a - b)) result.push({ path: file, line });
    }
    return result;
  }

  private sendResponse(request: any, body?: any): void {
    this.emitter.fire({
      seq: this.sequence++,
      type: 'response',
      request_seq: request.seq,
      success: true,
      command: request.command,
      ...(body === undefined ? {} : { body })
    });
  }

  private sendError(request: any, message: string): void {
    this.emitter.fire({
      seq: this.sequence++,
      type: 'response',
      request_seq: request.seq,
      success: false,
      command: request.command,
      message
    });
  }

  private sendEvent(event: string, body?: any): void {
    this.emitter.fire({ seq: this.sequence++, type: 'event', event, ...(body === undefined ? {} : { body }) });
  }

  private cleanupController(): void {
    if (!this.controllerPath) return;
    try { fs.rmSync(path.dirname(this.controllerPath), { recursive: true, force: true }); } catch { /* already gone */ }
    this.controllerPath = undefined;
  }

  private stop(sendTerminated: boolean): void {
    this.rejectInspection(new Error('Debugger terminated.'));
    const child = this.child;
    this.child = undefined;
    if (child && !child.killed) child.kill('SIGTERM');
    this.cleanupController();
    this.closeTerminal();
    this.atPrompt = false;
    this.stopped = undefined;
    this.pendingStop = undefined;
    if (sendTerminated && !this.terminated) {
      this.terminated = true;
      this.sendEvent('terminated');
    }
  }

  public dispose(): void {
    this.stop(false);
    this.emitter.dispose();
    this.sourceTerminalWrite.dispose();
  }
}
