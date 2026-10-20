import { ChildProcessWithoutNullStreams, spawn } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { setTimeout as retryDelay } from 'timers/promises';
import { hasProject, hexEncode, libraryArguments, projectFile, requireProject, resolveExecutable, workspaceRoot } from './util';
import { RuntimeConnection, RuntimeObserver } from './transport';
import { ReportProgress, RuntimeProgress } from './progress';
export { projectFile } from './util';

class WorkspaceRuntime implements vscode.Disposable {
  private process?: ChildProcessWithoutNullStreams;
  private executable?: string;
  private socketPath?: string;
  private socketDirectory?: string;
  private starting?: Promise<void>;
  private startup?: AbortController;
  private stderr = '';
  private disposed = false;
  public lifecycle = 0;
  public revision = 0;
  private readonly connections = new Set<RuntimeConnection>();
  private readonly inspections = new Map<string, { revision: number; source: string; promise: Promise<string>; controller: AbortController; users: number; done: boolean }>();
  private readonly inspectionSessions = new Map<string, { connection?: RuntimeConnection; queue: Promise<void>; busy: number }>();
  private readonly executions = new Set<Promise<unknown>>();
  private executionQueue: Promise<void> = Promise.resolve();

  constructor(private readonly output: vscode.OutputChannel,
    private readonly prepareExecutable: (uri: vscode.Uri) => Promise<string>,
    private readonly progress: RuntimeProgress) {}

  public async inspect(document: vscode.TextDocument, trace = true, signal?: AbortSignal, uri = document.uri): Promise<string> {
    signal?.throwIfAborted();
    if (!hasProject(uri)) { this.stop(); return ''; }
    const source = document.getText();
    await this.ensureStarted(uri);
    signal?.throwIfAborted();
    const key = `${trace}:${document.uri.fsPath}`;
    let entry = this.inspections.get(key);
    if (!entry || entry.source !== source) {
      if (entry && !entry.users && !entry.done) entry.controller.abort(new vscode.CancellationError());
      const controller = new AbortController();
      const command = `${trace ? ':trace' : ':inspect'}\t${hexEncode(document.uri.fsPath)}\t${hexEncode(source)}`;
      const timeout = vscode.workspace.getConfiguration('recurloop', uri).get('analysis.timeoutMs', 60000) as number;
      entry = { revision: this.revision, source, controller, users: 0, done: false,
        promise: this.inspectRequest(document.uri.fsPath, command, timeout, controller.signal) };
      const current = entry;
      this.inspections.set(key, current);
      current.promise.then(() => { current.done = true; }, () => {
        current.done = true;
        if (this.inspections.get(key) === current) this.inspections.delete(key);
      });
    }
    const current = entry;
    current.users++;
    return new Promise<string>((resolve, reject) => {
      let settled = false;
      const finish = (error?: unknown, value?: string) => {
        if (settled) return;
        settled = true;
        signal?.removeEventListener('abort', aborted);
        if (!error && current.revision !== this.revision) error = new vscode.CancellationError();
        if (--current.users === 0 && !current.done) {
          if (this.inspections.get(key) === current) this.inspections.delete(key);
          current.controller.abort(new vscode.CancellationError());
        }
        this.trimInspections();
        if (error) reject(error); else resolve(value!);
      };
      const aborted = () => finish(signal!.reason);
      signal?.addEventListener('abort', aborted, { once: true });
      current.promise.then(value => finish(undefined, value), error => finish(error));
      if (signal?.aborted) aborted();
    });
  }

  private trimInspections(): void {
    // Active consumers retain their work; completed traces have a fixed bound.
    if (this.inspections.size <= 128) return;
    for (const [key, entry] of this.inspections) {
      if (entry.done && !entry.users) this.inspections.delete(key);
      if (this.inspections.size <= 128) break;
    }
  }

  private inspectRequest(file: string, command: string, timeout: number, signal: AbortSignal): Promise<string> {
    let session = this.inspectionSessions.get(file);
    if (!session) session = { queue: Promise.resolve(), busy: 0 };
    // Keep each file's source-entry context, including while another file is
    // analyzed. Requests on one private server session are always serialized.
    this.inspectionSessions.delete(file);
    this.inspectionSessions.set(file, session);
    const current = session;
    current.busy++;
    const task = current.queue.then(() => {
      signal.throwIfAborted();
      if (!current.connection) current.connection = new RuntimeConnection(this.socketPath!, () => {
        current.connection = undefined;
      });
      return current.connection.request([command], timeout, signal);
    });
    current.queue = task.then(() => undefined, () => undefined);
    return task.finally(() => {
      current.busy--;
      // Bound retained contexts, while active requests keep their sessions.
      for (const [key, retained] of this.inspectionSessions) {
        if (this.inspectionSessions.size <= 8) break;
        if (!retained.busy) { retained.connection?.close(); this.inspectionSessions.delete(key); }
      }
    });
  }

  public async highlight(document: vscode.TextDocument): Promise<string> {
    if (!hasProject(document.uri)) return '';
    const source = document.getText();
    await this.ensureStarted(document.uri);
    const revision = this.revision;
    const timeout = vscode.workspace.getConfiguration('recurloop', document.uri).get('analysis.timeoutMs', 60000) as number;
    const response = await this.inspectRequest('\0palette', `:highlight\t${hexEncode(source)}`, timeout, new AbortController().signal);
    if (this.revision !== revision) throw new vscode.CancellationError();
    return response;
  }

  private invalidateInspections(): void {
    this.revision++;
    for (const entry of this.inspections.values()) if (!entry.done) entry.controller.abort(new vscode.CancellationError());
    this.inspections.clear();
    for (const session of this.inspectionSessions.values()) session.connection?.close();
    this.inspectionSessions.clear();
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
    const configured = resolveExecutable(uri);
    const executable = this.executable ?? configured;
    const state = this.process && !this.process.killed ? `running pid=${this.process.pid}` : 'stopped';
    return `executable=${executable}${executable !== configured ? `\nconfigured executable=${configured}` : ''}\nruntime=${state}\nsocket=${this.socketPath ?? '-'}${this.stderr ? `\nlast stderr=${this.stderr.trim()}` : ''}`;
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const request = this.executionQueue.then(operation);
    // A failed or cancelled request must not block subsequent work.
    this.executionQueue = request.then(() => undefined, () => undefined);
    this.executions.add(request);
    return request.finally(() => { this.executions.delete(request); });
  }

  public async execute(uri: vscode.Uri, commands: string[], signal?: AbortSignal): Promise<string> {
    signal?.throwIfAborted();
    await this.ensureStarted(uri);
    return this.enqueue(async () => {
      signal?.throwIfAborted();
      return this.request(this.socketPath!, commands, 120000, signal);
    });
  }

  public async reload(uri: vscode.Uri, signal?: AbortSignal): Promise<void> {
    signal?.throwIfAborted();
    if (!hasProject(uri)) { this.stop(); return; }
    // Startup may install the runtime through maintenance. Only ready requests
    // enter the queue that maintenance drains, avoiding a dependency cycle.
    await this.ensureStarted(uri);
    return this.enqueue(async () => {
      signal?.throwIfAborted();
      await this.progress(uri, 'Reloading project', async report => {
        await this.loadProject(uri, this.socketPath!, report, signal);
        this.invalidateInspections();
      });
    });
  }

  public async terminalOptions(uri: vscode.Uri): Promise<vscode.TerminalOptions> {
    await this.ensureStarted(uri);
    return { name: 'RecurLoop', cwd: workspaceRoot(uri), shellPath: this.executable!,
      shellArgs: ['--connect', this.socketPath!], env: { NO_COLOR: null } };
  }

  private async ensureStarted(uri: vscode.Uri): Promise<void> {
    if (!hasProject(uri)) this.stop();
    requireProject(uri);
    if (this.disposed) throw new Error('RecurLoop runtime is disposed');
    if (this.starting) return this.starting;
    if (this.process && !this.process.killed && this.socketPath && fs.existsSync(this.socketPath)) return;
    this.starting = this.progress(uri, 'Starting project', report => this.start(uri, report))
      .finally(() => { this.starting = undefined; });
    return this.starting;
  }

  private async start(uri: vscode.Uri, report: ReportProgress): Promise<void> {
    this.stop();
    const lifecycle = this.lifecycle;
    report('Preparing runtime');
    const executable = await this.prepareExecutable(uri);
    if (this.disposed) throw new Error('RecurLoop runtime is disposed');
    if (lifecycle !== this.lifecycle) throw new Error('RecurLoop server startup cancelled');
    this.executable = executable;
    requireProject(uri);
    const root = workspaceRoot(uri);
    this.socketDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-vscode-'));
    const socketPath = path.join(this.socketDirectory, 'runtime.sock');

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
      startup.abort(new Error(`RecurLoop server exited before startup completed (code=${code ?? '-'}, signal=${signal ?? '-'}). ${this.stderr.trim()}`));
      if (this.process === child) this.stop();
    });
    child.on('error', error => {
      this.stderr = error.message;
      this.output.appendLine(`[analysis] failed to start: ${error.message}`);
      startup.abort(error);
    });

    try {
      // A bound socket is not proof that the server is accepting clients. Its
      // protocol greeting is the readiness signal; elapsed time never is.
      report('Waiting for runtime connection');
      await this.waitForServer(socketPath, startup.signal);
      requireProject(uri);
      await this.loadProject(uri, socketPath, report, startup.signal);
      this.output.appendLine('[analysis] server ready; project published');
    } catch (error) {
      this.stop();
      throw error;
    } finally {
      if (this.startup === startup) this.startup = undefined;
    }
  }

  private async loadProject(uri: vscode.Uri, socketPath: string, report: ReportProgress, signal?: AbortSignal): Promise<void> {
    const stages = ['Restoring baseline', 'Preparing project cache', 'Loading project files', 'Publishing project'];
    const commands = [':baseline', ':cache', `:load-file-progress\t${projectFile(uri)}`, ':publish'];
    let completed = 0;
    let pending = '';
    const status = (detail?: string) => {
      report(`${completed}/${stages.length} stages complete; ${stages.length - completed} remaining — ${detail ?? stages[completed] ?? 'Ready'}`);
    };
    status();
    await this.request(socketPath, commands, 120000, signal, {
      output: text => { if (text) this.output.append(text); },
      progress: text => {
        pending += text;
        for (;;) {
          const end = pending.indexOf('\n');
          if (end < 0) break;
          const line = pending.slice(0, end);
          pending = pending.slice(end + 1);
          if (line) status(line);
        }
      },
      completed: count => { completed = count; status(); }
    });
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

  private async request(socketPath: string, command: string | string[], timeoutMs?: number, signal?: AbortSignal,
    observer?: RuntimeObserver): Promise<string> {
    const connection = new RuntimeConnection(socketPath);
    try { return await connection.request(Array.isArray(command) ? command : [command], timeoutMs, signal, observer); }
    finally { connection.close(); }
  }

  public async openAnalysis(uri: vscode.Uri): Promise<RuntimeConnection> {
    await this.ensureStarted(uri);
    const connection = new RuntimeConnection(this.socketPath!, () => this.connections.delete(connection));
    this.connections.add(connection);
    return connection;
  }

  private stop(): void {
    this.lifecycle++;
    this.invalidateInspections();
    for (const connection of this.connections) connection.close();
    this.connections.clear();
    this.startup?.abort(new Error('RecurLoop server startup cancelled'));
    this.startup = undefined;
    const child = this.process;
    this.process = undefined;
    this.executable = undefined;
    if (child && !child.killed) child.kill('SIGTERM');
    if (this.socketDirectory) {
      try { fs.rmSync(this.socketDirectory, { recursive: true, force: true }); } catch { /* already removed */ }
    }
    this.socketDirectory = undefined;
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
    private readonly prepareExecutable: (uri: vscode.Uri) => Promise<string> = async uri => resolveExecutable(uri),
    private readonly progress: RuntimeProgress = async (_uri, _title, task) => task(() => {})) {}
  private runtime(uri: vscode.Uri): WorkspaceRuntime {
    const key = workspaceRoot(uri);
    let runtime = this.workspaces.get(key);
    if (!runtime) { runtime = new WorkspaceRuntime(this.output, this.prepareExecutable, this.progress); this.workspaces.set(key, runtime); }
    return runtime;
  }
  private afterMaintenance<T>(operation: () => Promise<T>): Promise<T> {
    if (this.maintenance) return this.maintenance.then(() => this.afterMaintenance(operation));
    return operation();
  }
  inspect(document: vscode.TextDocument, trace = true, signal?: AbortSignal, uri = document.uri): Promise<string> { return this.afterMaintenance(() => this.runtime(uri).inspect(document, trace, signal, uri)); }
  highlight(document: vscode.TextDocument): Promise<string> { return this.afterMaintenance(() => this.runtime(document.uri).highlight(document)); }
  revision(uri: vscode.Uri): number { return this.runtime(uri).revision; }
  epoch(uri: vscode.Uri): number { return this.runtime(uri).lifecycle; }
  openAnalysis(uri: vscode.Uri): Promise<RuntimeConnection> { return this.afterMaintenance(() => this.runtime(uri).openAnalysis(uri)); }
  execute(uri: vscode.Uri, commands: string[], signal?: AbortSignal): Promise<string> { return this.afterMaintenance(() => this.runtime(uri).execute(uri, commands, signal)); }
  terminalOptions(uri: vscode.Uri): Promise<vscode.TerminalOptions> { return this.afterMaintenance(() => this.runtime(uri).terminalOptions(uri)); }
  reload(uri: vscode.Uri, signal?: AbortSignal): Promise<void> { return this.afterMaintenance(() => this.runtime(uri).reload(uri, signal)); }
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
