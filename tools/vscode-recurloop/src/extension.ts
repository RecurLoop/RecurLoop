import * as vscode from 'vscode';
import { AnalysisController } from './analysis';
import { RecurLoopDebugAdapter } from './debugAdapter';
import { ProjectController, TargetRunAdapter } from './project';
import { RecurLoopRuntime } from './runtime';
import { resolveExecutable, shellQuote, workspaceRoot } from './util';

export class DebugConfigurationProvider implements vscode.DebugConfigurationProvider {
  constructor(private readonly project: ProjectController) {}
  provideDebugConfigurations(folder: vscode.WorkspaceFolder | undefined): vscode.ProviderResult<vscode.DebugConfiguration[]> {
    return folder ? this.project.debugConfigurations(folder) : [];
  }
  async resolveDebugConfiguration(folder: vscode.WorkspaceFolder | undefined, config: vscode.DebugConfiguration): Promise<vscode.DebugConfiguration | undefined> {
    const editor = vscode.window.activeTextEditor;
    if (config.target && folder) {
      await this.project.resolveTarget(folder, config);
      if (config.projectTarget) return config;
    }
    if (!config.type && editor?.document.languageId === 'recurloop') {
      config.type = 'recurloop';
      config.request = 'launch';
      config.name = 'RecurLoop: Debug current file';
      config.program = editor.document.uri.fsPath;
    }
    if (config.type !== 'recurloop') return config;
    if (!config.program && !config.executable && editor?.document.languageId === 'recurloop') config.program = editor.document.uri.fsPath;
    if (!config.cwd) config.cwd = folder?.uri.fsPath ?? workspaceRoot(editor?.document.uri);
    if (!config.recurloop) config.recurloop = resolveExecutable(folder?.uri ?? editor?.document.uri);
    if (!config.program && !config.executable) {
      void vscode.window.showErrorMessage('Open a RecurLoop file or set "program"/"executable" in the RecurLoop debug configuration.');
      return undefined;
    }
    return config;
  }
}

class DebugFactory implements vscode.DebugAdapterDescriptorFactory, vscode.Disposable {
  private readonly adapters = new Map<string, RecurLoopDebugAdapter | TargetRunAdapter>();
  private readonly termination: vscode.Disposable;

  constructor(private readonly output: vscode.OutputChannel, private readonly project: ProjectController) {
    this.termination = vscode.debug.onDidTerminateDebugSession(session => {
      this.adapters.get(session.id)?.dispose();
      this.adapters.delete(session.id);
    });
  }

  createDebugAdapterDescriptor(session: vscode.DebugSession): vscode.ProviderResult<vscode.DebugAdapterDescriptor> {
    const adapter = session.configuration.projectTarget
      ? new TargetRunAdapter(this.project, session.workspaceFolder!.uri)
      : new RecurLoopDebugAdapter(this.output);
    this.adapters.set(session.id, adapter);
    return new vscode.DebugAdapterInlineImplementation(adapter);
  }

  dispose(): void {
    this.termination.dispose();
    for (const adapter of this.adapters.values()) adapter.dispose();
    this.adapters.clear();
  }
}

export function activate(context: vscode.ExtensionContext): void {
  const output = vscode.window.createOutputChannel('RecurLoop');
  const runtime = new RecurLoopRuntime(output);
  const analysis = new AnalysisController(runtime, output);
  const project = new ProjectController(runtime);
  const debugFactory = new DebugFactory(output, project);

  context.subscriptions.push(
    vscode.tasks.registerTaskProvider('recurloop', project),
    vscode.debug.registerDebugConfigurationProvider('recurloop', new DebugConfigurationProvider(project), vscode.DebugConfigurationProviderTriggerKind.Dynamic),
    vscode.window.registerTerminalProfileProvider('recurloop.console', {
      provideTerminalProfile: async () => {
        const uri = vscode.window.activeTextEditor?.document.uri ?? vscode.workspace.workspaceFolders?.[0]?.uri;
        if (!uri) throw new Error('Open a workspace for the RecurLoop project console.');
        return new vscode.TerminalProfile(await runtime.terminalOptions(uri));
      }
    }),
    vscode.commands.registerCommand('recurloop.openConsole', async () => {
      const uri = vscode.window.activeTextEditor?.document.uri ?? vscode.workspace.workspaceFolders?.[0]?.uri;
      if (uri) vscode.window.createTerminal(await runtime.terminalOptions(uri)).show();
    }),
    output,
    runtime,
    analysis,
    debugFactory,
    vscode.debug.registerDebugConfigurationProvider('recurloop', new DebugConfigurationProvider(project)),
    vscode.debug.registerDebugAdapterDescriptorFactory('recurloop', debugFactory),
    vscode.commands.registerCommand('recurloop.runCurrentFile', () => runCurrentFile()),
    vscode.commands.registerCommand('recurloop.debugCurrentFile', () => debugCurrentFile()),
    vscode.commands.registerCommand('recurloop.restartLanguageRuntime', async () => {
      const uri = vscode.window.activeTextEditor?.document.uri;
      try {
        await runtime.restart(uri);
        analysis.invalidate();
        void vscode.window.showInformationMessage('RecurLoop language runtime restarted.');
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        output.appendLine(`[analysis] restart failed: ${message}`);
        output.show(true);
        void vscode.window.showErrorMessage(message);
      }
    }),
    vscode.commands.registerCommand('recurloop.showRuntimeInfo', () => {
      const uri = vscode.window.activeTextEditor?.document.uri;
      output.appendLine(runtime.info(uri));
      output.show(true);
    }),
    vscode.workspace.onDidChangeConfiguration(event => {
      if (event.affectsConfiguration('recurloop.executablePath') || event.affectsConfiguration('recurloop.analysis') || event.affectsConfiguration('recurloop.projectFile') || event.affectsConfiguration('recurloop.terminal.libraries')) {
        for (const folder of vscode.workspace.workspaceFolders ?? []) {
          if (event.affectsConfiguration('recurloop', folder.uri)) {
            void runtime.restart(folder.uri).then(() => analysis.invalidate()).catch(error => output.appendLine(String(error)));
          }
        }
      }
    })
  );
  const pending = new Map<string, NodeJS.Timeout>();
  const changed = (uri: vscode.Uri) => {
    if (/[\\/](?:\.cache|node_modules|\.git)[\\/]/.test(uri.fsPath)) return;
    const root = workspaceRoot(uri);
    clearTimeout(pending.get(root));
    pending.set(root, setTimeout(() => {
      pending.delete(root);
      void runtime.reload(uri).then(() => analysis.invalidate()).catch(error => output.appendLine(String(error)));
    }, 250));
  };
  const watcher = vscode.workspace.createFileSystemWatcher('**/*.{rl,rli}');
  context.subscriptions.push(watcher, watcher.onDidChange(changed), watcher.onDidCreate(changed),
    watcher.onDidDelete(changed), { dispose: () => { for (const timer of pending.values()) clearTimeout(timer); } });
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    void runtime.restart(folder.uri).catch(error => output.appendLine(String(error)));
  }
}

async function runCurrentFile(): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== 'recurloop') {
    void vscode.window.showErrorMessage('Open a RecurLoop file first.');
    return;
  }
  if (editor.document.isDirty) await editor.document.save();
  const executable = resolveExecutable(editor.document.uri);
  const root = workspaceRoot(editor.document.uri);
  const terminal = vscode.window.createTerminal({ name: 'RecurLoop', cwd: root });
  terminal.show();
  terminal.sendText(`${shellQuote(executable)} --file ${shellQuote(editor.document.uri.fsPath)}`);
}

async function debugCurrentFile(): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== 'recurloop') {
    void vscode.window.showErrorMessage('Open a RecurLoop file first.');
    return;
  }
  if (editor.document.isDirty) await editor.document.save();
  const folder = vscode.workspace.getWorkspaceFolder(editor.document.uri);
  await vscode.debug.startDebugging(folder, {
    type: 'recurloop',
    request: 'launch',
    name: `RecurLoop: ${editor.document.fileName.split(/[\\/]/).pop()}`,
    program: editor.document.uri.fsPath,
    cwd: folder?.uri.fsPath ?? workspaceRoot(editor.document.uri)
  });
}

export function deactivate(): void {
  // Disposables registered in the extension context own all runtime resources.
}
