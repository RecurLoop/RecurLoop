import { ChildProcessWithoutNullStreams, spawn } from 'child_process';
import * as fs from 'fs';
import * as net from 'net';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { setTimeout as retryDelay } from 'timers/promises';
import { hasProject, hexEncode, libraryArguments, projectFile, requireProject, resolveExecutable, workspaceRoot } from './util';
export { projectFile } from './util';

class WorkspaceRuntime implements vscode.Disposable {
  private process?: ChildProcessWithoutNullStreams;
  private executable?: string;
  private socketPath?: string;
  private starting?: Promise<void>;
  private startup?: AbortController;
  private stderr = '';
  private disposed = false;
  private lifecycle = 0;
  private readonly executions = new Set<Promise<string>>();

  constructor(private readonly output: vscode.OutputChannel,
    private readonly prepareExecutable: (uri: vscode.Uri) => Promise<string>) {}

  public async inspect(document: vscode.TextDocument, trace = true): Promise<string> {
    if (!hasProject(document.uri)) { this.stop(); return ''; }
    await this.ensureStarted(document.uri);
    const socketPath = this.socketPath;
    if (!socketPath) throw new Error('RecurLoop analysis runtime did not create a socket');

    const command = `${trace ? ':trace' : ':inspect'}\t${hexEncode(document.uri.fsPath)}\t${hexEncode(document.getText())}`;
    const timeout = vscode.workspace.getConfiguration('recurloop', document.uri).get('analysis.timeoutMs', 5000) as number;
    return this.request(socketPath, command, timeout);
  }

  public async restart(uri?: vscode.Uri): Promise<void> {
    if (!uri || !hasProject(uri)) this.stop();
    if (this.starting) await this.starting.catch(() => undefined);
    await Promise.allSettled([...this.executions]);
    this.stop();
    if (uri && hasProject(uri)) await this.ensureStarted(uri);
  }

  public async stopWhenIdle(): Promise<void> {
    const hadProcess = !!this.process;
    if (this.startup) this.stop();
    // Setup may itself be waiting for maintenance to promote a download.
    // No child exists yet in that case, so do not await that startup here.
    if (hadProcess && this.starting) await this.starting.catch(() => undefined);
    // Let requests that already passed ensureStarted register their execution
    // before taking the snapshot. Maintenance blocks all subsequent clients.
    await Promise.resolve();
    await Promise.allSettled([...this.executions]);
    this.stop();
  }

  public usesExecutable(predicate: (executable: string) => boolean): boolean {
    return !!this.executable && predicate(this.executable);
  }

  public info(uri?: vscode.Uri): string {
    const executable = resolveExecutable(uri);
    const state = this.process && !this.process.killed ? `running pid=${this.process.pid}` : 'stopped';
    return `executable=${executable}\nruntime=${state}\nsocket=${this.socketPath ?? '-'}${this.stderr ? `\nlast stderr=${this.stderr.trim()}` : ''}`;
  }

  public async execute(uri: vscode.Uri, commands: string[]): Promise<string> {
    await this.ensureStarted(uri);
    const request = this.request(this.socketPath!, commands, 120000);
    this.executions.add(request);
    try { return await request; } finally { this.executions.delete(request); }
  }

  public async reload(uri: vscode.Uri): Promise<void> {
    if (!hasProject(uri)) { this.stop(); return; }
    await this.ensureStarted(uri);
    await Promise.allSettled([...this.executions]);
    const entry = projectFile(uri);
    const commands = [':baseline', ':cache'];
    if (fs.existsSync(entry)) commands.push(`:load-file\t${entry}`);
    commands.push(':publish');
    await this.execute(uri, commands);
  }

  public async terminalOptions(uri: vscode.Uri): Promise<vscode.TerminalOptions> {
    await this.ensureStarted(uri);
    return { name: 'RecurLoop', cwd: workspaceRoot(uri), shellPath: resolveExecutable(uri),
      shellArgs: ['--connect', this.socketPath!], env: { NO_COLOR: null } };
  }

  private async ensureStarted(uri: vscode.Uri): Promise<void> {
    if (!hasProject(uri)) this.stop();
    requireProject(uri);
    if (this.disposed) throw new Error('RecurLoop runtime is disposed');
    if (this.starting) return this.starting;
    if (this.process && !this.process.killed && this.socketPath && fs.existsSync(this.socketPath)) return;
    this.starting = this.start(uri).finally(() => { this.starting = undefined; });
    return this.starting;
  }

  private async start(uri: vscode.Uri): Promise<void> {
    this.stop();
    const lifecycle = this.lifecycle;
    const executable = await this.prepareExecutable(uri);
    if (this.disposed) throw new Error('RecurLoop runtime is disposed');
    if (lifecycle !== this.lifecycle) throw new Error('RecurLoop server startup cancelled');
    this.executable = executable;
    requireProject(uri);
    const root = workspaceRoot(uri);
    const suffix = `${process.pid}-${Math.random().toString(16).slice(2, 8)}`;
    const socketPath = path.join(os.tmpdir(), `rl-vscode-${suffix}.sock`);
    try { fs.unlinkSync(socketPath); } catch { /* absent */ }

    const project = projectFile(uri);
    const args = ['--library', 'project', ...libraryArguments(uri), '--project-cache',
      path.join(root, '.cache', 'recurloop'), '--serve', '--unix', socketPath, '--no-stdio'];
    this.output.appendLine(`[analysis] starting ${executable} --serve --unix ${socketPath} --no-stdio`);
    const child = spawn(executable, args, {
      cwd: root,
      env: { ...process.env, NO_COLOR: '1', RECURLOOP_PROJECT_ROOT: root },
      stdio: ['pipe', 'pipe', 'pipe']
    });
    this.process = child;
    const startup = new AbortController();
    this.startup = startup;
    this.socketPath = socketPath;
    this.stderr = '';

    child.stdout.on('data', chunk => {
      const text = chunk.toString();
      if (text.trim()) this.output.append(`[analysis stdout] ${text}`);
    });
    child.stderr.on('data', chunk => {
      const text = chunk.toString();
      this.stderr = (this.stderr + text).slice(-8000);
      this.output.append(`[analysis stderr] ${text}`);
    });
    child.on('exit', (code, signal) => {
      this.output.appendLine(`[analysis] runtime exited code=${code ?? '-'} signal=${signal ?? '-'}`);
      if (this.process === child) this.process = undefined;
      startup.abort(new Error(`RecurLoop server exited before startup completed (code=${code ?? '-'}, signal=${signal ?? '-'}). ${this.stderr.trim()}`));
    });
    child.on('error', error => {
      this.stderr = error.message;
      this.output.appendLine(`[analysis] failed to start: ${error.message}`);
      startup.abort(error);
    });

    try {
      // A bound socket is not proof that the server is accepting clients. Its
      // protocol greeting is the readiness signal; elapsed time never is.
      await this.waitForServer(socketPath, startup.signal);
      requireProject(uri);
      await this.request(socketPath, [':baseline', ':cache', `:load-file\t${project}`, ':publish'], 120000, startup.signal);
      this.output.appendLine('[analysis] server ready; project published');
    } catch (error) {
      this.stop();
      throw error;
    } finally {
      if (this.startup === startup) this.startup = undefined;
    }
  }

  private async waitForServer(socketPath: string, signal: AbortSignal): Promise<void> {
    for (;;) {
      signal.throwIfAborted();
      try {
        await this.request(socketPath, [], undefined, signal);
        return;
      } catch (error) {
        signal.throwIfAborted();
        const code = (error as NodeJS.ErrnoException).code;
        if (!['ENOENT', 'ECONNREFUSED', 'ECONNRESET', 'EPIPE'].includes(code ?? '')) throw error;
        // Back off between connection attempts, without a startup deadline.
        try { await retryDelay(25, undefined, { signal }); }
        catch (error) { signal.throwIfAborted(); throw error; }
      }
    }
  }

  private request(socketPath: string, command: string | string[], timeoutMs?: number, signal?: AbortSignal): Promise<string> {
    return new Promise((resolve, reject) => {
      if (signal?.aborted) { reject(signal.reason); return; }
      const socket = net.createConnection(socketPath);
      let buffer = Buffer.alloc(0);
      let ready = false;
      let status: number | undefined;
      let chunks: Buffer[] = [];
      const commands = Array.isArray(command) ? [...command] : [command];
      let result = '';
      const sendNext = () => socket.write(commands.shift()! + '\n');
      let settled = false;
      const timer = timeoutMs === undefined ? undefined
        : setTimeout(() => finish(new Error(`RecurLoop analysis request timed out after ${timeoutMs} ms`)), timeoutMs);
      const aborted = () => finish(signal!.reason);

      const finish = (error?: Error, value = '') => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        signal?.removeEventListener('abort', aborted);
        socket.destroy();
        if (error) reject(error); else resolve(value);
      };
      signal?.addEventListener('abort', aborted, { once: true });

      socket.on('data', chunk => {
        buffer = Buffer.concat([buffer, chunk]);
        if (!ready) {
          if (buffer.length < 2) return;
          if (buffer.subarray(0, 2).toString() !== '> ') { finish(new Error('Invalid RecurLoop server greeting')); return; }
          ready = true;
          buffer = buffer.subarray(2);
          if (!commands.length) { finish(undefined, ''); return; }
          socket.write(':transport-stream-v2\n');
          sendNext();
        }
        while (buffer.length >= 5) {
          const kind = buffer[0];
          const length = buffer.readUInt32BE(1);
          if (length > 4096) { finish(new Error('Invalid RecurLoop response frame')); return; }
          if (buffer.length < 5 + length) return;
          const payload = buffer.subarray(5, 5 + length);
          buffer = buffer.subarray(5 + length);
          if (kind === 79) chunks.push(payload); // O: output, including arbitrary prompt text and split UTF-8
          else if (kind === 83 && /^-?\d+$/.test(payload.toString('ascii'))) status = Number(payload.toString('ascii'));
          else if (kind === 80 && !length && status !== undefined) {
            const reply = Buffer.concat(chunks).toString('utf8');
            if (status !== 0) { finish(new Error(`${reply}\nstatus=${status}`)); return; }
            result += reply;
            chunks = []; status = undefined;
            if (commands.length) sendNext(); else { finish(undefined, result); return; }
          } else { finish(new Error('Invalid RecurLoop response frame')); return; }
        }
      });
      socket.on('error', error => finish(error));
      socket.on('end', () => {
        if (!settled) finish(Object.assign(new Error('RecurLoop analysis runtime closed the socket before replying'),
          { code: ready ? undefined : 'ECONNRESET' }));
      });
    });
  }

  private stop(): void {
    this.lifecycle++;
    this.startup?.abort(new Error('RecurLoop server startup cancelled'));
    this.startup = undefined;
    const child = this.process;
    this.process = undefined;
    this.executable = undefined;
    if (child && !child.killed) child.kill('SIGTERM');
    if (this.socketPath) {
      try { fs.unlinkSync(this.socketPath); } catch { /* absent or already removed */ }
    }
    this.socketPath = undefined;
  }

  public dispose(): void {
    this.disposed = true;
    this.stop();
  }
}

/** Each workspace owns a separate published language environment. */
export class RecurLoopRuntime implements vscode.Disposable {
  private readonly workspaces = new Map<string, WorkspaceRuntime>();
  private maintenance?: Promise<void>;
  constructor(private readonly output: vscode.OutputChannel,
    private readonly prepareExecutable: (uri: vscode.Uri) => Promise<string> = async uri => resolveExecutable(uri)) {}
  private runtime(uri: vscode.Uri): WorkspaceRuntime {
    const key = workspaceRoot(uri);
    let runtime = this.workspaces.get(key);
    if (!runtime) { runtime = new WorkspaceRuntime(this.output, this.prepareExecutable); this.workspaces.set(key, runtime); }
    return runtime;
  }
  private afterMaintenance<T>(operation: () => Promise<T>): Promise<T> {
    if (this.maintenance) return this.maintenance.then(() => this.afterMaintenance(operation));
    return operation();
  }
  inspect(document: vscode.TextDocument, trace = true): Promise<string> { return this.afterMaintenance(() => this.runtime(document.uri).inspect(document, trace)); }
  execute(uri: vscode.Uri, commands: string[]): Promise<string> { return this.afterMaintenance(() => this.runtime(uri).execute(uri, commands)); }
  terminalOptions(uri: vscode.Uri): Promise<vscode.TerminalOptions> { return this.afterMaintenance(() => this.runtime(uri).terminalOptions(uri)); }
  reload(uri: vscode.Uri): Promise<void> { return this.afterMaintenance(() => this.runtime(uri).reload(uri)); }
  restart(uri?: vscode.Uri): Promise<void> {
    return this.afterMaintenance(async () => {
      if (uri) await this.runtime(uri).restart(uri);
      else { for (const runtime of this.workspaces.values()) runtime.dispose(); this.workspaces.clear(); }
    });
  }
  /** Pause new clients and drain active targets before replacing or removing managed files. */
  async maintain<T>(operation: () => Promise<T>, selected?: (executable: string) => boolean): Promise<T> {
    while (this.maintenance) await this.maintenance;
    let release!: () => void;
    this.maintenance = new Promise<void>(resolve => { release = resolve; });
    try {
      const affected = [...this.workspaces.values()].filter(runtime => !selected || runtime.usesExecutable(selected));
      await Promise.all(affected.map(runtime => runtime.stopWhenIdle()));
      return await operation();
    } finally {
      this.maintenance = undefined;
      release();
    }
  }
  info(uri?: vscode.Uri): string { return uri ? this.runtime(uri).info(uri) : 'Select a workspace to inspect its runtime.'; }
  dispose(): void { for (const runtime of this.workspaces.values()) runtime.dispose(); this.workspaces.clear(); }
}
