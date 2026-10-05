import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { RecurLoopRuntime, projectFile } from './runtime';
import { hasProject, workspaceRoot } from './util';

export interface ProjectTarget {
  name: string;
  dependencies?: string[];
  command: string;
  debugProgram?: string;
  debugExecutable?: string;
}

export class ProjectController implements vscode.TaskProvider {
  constructor(private readonly runtime: RecurLoopRuntime) {}

  async targets(uri: vscode.Uri): Promise<ProjectTarget[]> {
    if (!hasProject(uri)) return [];
    if (!fs.readFileSync(projectFile(uri), 'utf8').trim()) return [];
    const response = await this.runtime.execute(uri, ['VSCode:describe project']);
    const value = JSON.parse(response.trim());
    const data = typeof value === 'string' ? JSON.parse(value) : value;
    if (!Array.isArray(data.targets)) throw new Error('VSCode:describe project must return JSON with a targets array.');
    const names = new Set<string>();
    for (const target of data.targets) {
      if (typeof target.name !== 'string' || !target.name || names.has(target.name) ||
          typeof target.command !== 'string' || /[\r\n]/.test(target.command) ||
          (target.debugExecutable !== undefined && typeof target.debugExecutable !== 'string') ||
          (target.debugProgram !== undefined && typeof target.debugProgram !== 'string') ||
          (target.dependencies !== undefined && (!Array.isArray(target.dependencies) ||
            target.dependencies.some((name: unknown) => typeof name !== 'string')))) {
        throw new Error('Invalid or duplicate target returned by VSCode:describe project.');
      }
      names.add(target.name);
    }
    return data.targets;
  }

  async run(uri: vscode.Uri, name: string): Promise<string> {
    await vscode.workspace.saveAll(false);
    // Allow the file watcher to begin publishing saved project changes first.
    await new Promise(resolve => setTimeout(resolve, 300));
    const targets = await this.targets(uri);
    const commands: string[] = [];
    const done = new Set<string>();
    const visiting = new Set<string>();
    const visit = (name: string) => {
      if (done.has(name)) return;
      if (visiting.has(name)) throw new Error(`Cyclic target dependency: ${name}`);
      const target = targets.find(target => target.name === name);
      if (!target) throw new Error(`Unknown RecurLoop target: ${name}`);
      visiting.add(name);
      for (const dependency of target.dependencies ?? []) visit(dependency);
      visiting.delete(name);
      done.add(name);
      if (target.command) commands.push(target.command);
    };
    visit(name);
    return commands.length ? this.runtime.execute(uri, commands) : '';
  }

  private task(folder: vscode.WorkspaceFolder, name: string, definition = { type: 'recurloop', target: name }): vscode.Task {
    return new vscode.Task(definition, folder, name, 'RecurLoop', new vscode.CustomExecution(async () => {
      const write = new vscode.EventEmitter<string>();
      const close = new vscode.EventEmitter<number>();
      let closed = false;
      return {
        onDidWrite: write.event, onDidClose: close.event,
        open: () => {
          void this.run(folder.uri, name).then(output => {
            if (!closed) { write.fire(output.replace(/\r?\n/g, '\r\n')); close.fire(0); }
          }, error => {
            if (!closed) { write.fire(`${String(error)}\r\n`); close.fire(1); }
          });
        },
        close: () => { closed = true; write.dispose(); close.dispose(); }
      };
    }), []);
  }

  async provideTasks(): Promise<vscode.Task[]> {
    const result: vscode.Task[] = [];
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
      try { for (const target of await this.targets(folder.uri)) result.push(this.task(folder, target.name)); }
      catch (error) { console.error(error); }
    }
    return result;
  }

  resolveTask(task: vscode.Task): vscode.Task | undefined {
    if (typeof task.definition.target !== 'string' || typeof task.scope !== 'object') return undefined;
    return this.task(task.scope, task.definition.target, task.definition as { type: string; target: string });
  }

  async debugConfigurations(folder: vscode.WorkspaceFolder): Promise<vscode.DebugConfiguration[]> {
    return (await this.targets(folder.uri)).map(target => ({
      type: 'recurloop', request: 'launch', name: `RecurLoop: ${target.name}`,
      target: target.name, cwd: workspaceRoot(folder.uri), noDebug: !(target.debugProgram || target.debugExecutable)
    }));
  }

  async resolveTarget(folder: vscode.WorkspaceFolder, config: vscode.DebugConfiguration): Promise<void> {
    const target = (await this.targets(folder.uri)).find(target => target.name === config.target);
    if (!target) throw new Error(`Unknown RecurLoop target: ${config.target}`);
    if ((target.debugProgram || target.debugExecutable) && !config.noDebug) {
      for (const dependency of target.dependencies ?? []) await this.run(folder.uri, dependency);
      if (target.debugProgram) config.program = path.resolve(workspaceRoot(folder.uri), target.debugProgram);
      if (target.debugExecutable) config.executable = path.resolve(workspaceRoot(folder.uri), target.debugExecutable);
      config.projectFile = projectFile(folder.uri);
    } else config.projectTarget = target.name;
  }
}

/** Run and Debug can launch server targets without creating a second language runtime. */
export class TargetRunAdapter implements vscode.DebugAdapter {
  private readonly emitter = new vscode.EventEmitter<any>();
  readonly onDidSendMessage = this.emitter.event;
  private sequence = 1;
  private disposed = false;
  private readonly terminalWrite = new vscode.EventEmitter<string>();
  private terminal?: vscode.Terminal;
  constructor(private readonly project: ProjectController, private readonly uri: vscode.Uri) {}
  handleMessage(message: any): void {
    if (message.type !== 'request') return;
    this.emitter.fire({ seq: this.sequence++, type: 'response', request_seq: message.seq,
      command: message.command, success: true, body: {} });
    if (message.command === 'launch') {
      this.terminal = vscode.window.createTerminal({ name: `RecurLoop: ${message.arguments.projectTarget}`,
        pty: { onDidWrite: this.terminalWrite.event, open: () => {
          void this.project.run(this.uri, message.arguments.projectTarget).then(
            output => this.finish(output), error => this.finish(String(error)));
        }, close: () => {} } });
      this.terminal.show(true);
    }
    if (message.command === 'disconnect' || message.command === 'terminate') this.finish('');
  }
  private finish(output: string): void {
    if (this.disposed) return;
    this.terminalWrite.fire(output.replace(/\r?\n/g, '\r\n'));
    this.emitter.fire({ seq: this.sequence++, type: 'event', event: 'terminated', body: {} });
  }
  dispose(): void { this.disposed = true; this.emitter.dispose(); this.terminalWrite.dispose(); }
}
