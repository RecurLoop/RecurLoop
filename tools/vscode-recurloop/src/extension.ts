import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { AnalysisController } from './analysis';
import { RecurLoopDebugAdapter } from './debugAdapter';
import { ProjectController, TargetRunAdapter } from './project';
import { RecurLoopRuntime } from './runtime';
import { RuntimeSetup } from './runtimeSetup';
import { hasProject, projectFile, resolveExecutable, shellQuote, workspaceRoot } from './util';

export class DebugConfigurationProvider implements vscode.DebugConfigurationProvider {
  constructor(private readonly project: ProjectController,
    private readonly prepareExecutable: (uri?: vscode.Uri, override?: string) => Promise<string> = async (uri, override) => resolveExecutable(uri, override)) {}
  provideDebugConfigurations(folder: vscode.WorkspaceFolder | undefined): vscode.ProviderResult<vscode.DebugConfiguration[]> {
    return folder ? this.project.debugConfigurations(folder) : [];
  }
  async resolveDebugConfiguration(folder: vscode.WorkspaceFolder | undefined, config: vscode.DebugConfiguration): Promise<vscode.DebugConfiguration | undefined | null> {
    const editor = vscode.window.activeTextEditor;
    if (!hasProject(folder?.uri ?? editor?.document.uri)) return null;
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
    if (!config.program && !config.executable) {
      void vscode.window.showErrorMessage('Open a RecurLoop file or set "program"/"executable" in the RecurLoop debug configuration.');
      return undefined;
    }
    config.recurloop = await this.prepareExecutable(folder?.uri ?? editor?.document.uri, config.recurloop);
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

/** Allocate runtime resources and language providers only after a project opts in. */
function createProjectFeatures(context: vscode.ExtensionContext) {
  const output = vscode.window.createOutputChannel('RecurLoop');
  const setup = new RuntimeSetup(context, output);
  const prepareExecutable = (uri?: vscode.Uri, override?: string) => setup.ensureExecutable(uri, override);
  const runtime = new RecurLoopRuntime(output, prepareExecutable);
  const analysis = new AnalysisController(runtime, output);
  const project = new ProjectController(runtime);
  const debugFactory = new DebugFactory(output, project);
  const debugProvider = new DebugConfigurationProvider(project, prepareExecutable);
  return { output, setup, runtime, analysis, project, debugFactory, debugProvider, prepareExecutable,
    dispose: () => {
      debugFactory.dispose();
      analysis.dispose();
      runtime.dispose();
      setup.dispose();
      output.dispose();
    }
  };
}

export function activate(context: vscode.ExtensionContext): void {
  let features: ReturnType<typeof createProjectFeatures> | undefined;
  const pending = new Map<string, NodeJS.Timeout>();
  const selectedUri = () => vscode.window.activeTextEditor?.document.uri ?? vscode.workspace.workspaceFolders?.[0]?.uri;
  const synchronize = () => {
    const enabled = (vscode.workspace.workspaceFolders ?? []).some(folder => hasProject(folder.uri));
    if (enabled && !features) features = createProjectFeatures(context);
    if (!enabled && features) { features.dispose(); features = undefined; }
    return features;
  };
  const report = (error: unknown, uri: vscode.Uri) => {
    if (hasProject(uri)) features?.output.appendLine(String(error));
  };
  const inProject = async (action: (active: NonNullable<typeof features>, uri: vscode.Uri) => Promise<void> | void) => {
    const uri = selectedUri();
    if (!uri || !hasProject(uri)) return;
    const active = synchronize();
    if (!active) return;
    try { await action(active, uri); }
    catch (error) {
      if (!hasProject(uri)) return;
      active.output.appendLine(String(error));
      if (!String(error).includes('setup was deferred')) void vscode.window.showErrorMessage(String(error));
    }
  };
  const changed = (uri: vscode.Uri) => {
    if (!vscode.workspace.getWorkspaceFolder(uri)) return;
    const entryChanged = uri.fsPath === projectFile(uri);
    if (!entryChanged && (!hasProject(uri) || !/\.(rl|rli)$/.test(uri.fsPath))) return;
    if (!entryChanged && /[\\/](?:\.cache|node_modules|\.git)[\\/]/.test(uri.fsPath)) return;
    const root = workspaceRoot(uri);
    clearTimeout(pending.get(root));
    pending.delete(root);
    const active = synchronize();
    if (!active) return;
    if (!hasProject(uri)) {
      void active.runtime.reload(uri).then(() => active.analysis.invalidate()).catch(error => report(error, uri));
      return;
    }
    pending.set(root, setTimeout(() => {
      pending.delete(root);
      const current = synchronize();
      if (!current || !hasProject(uri)) return;
      void current.runtime.reload(uri).then(() => current.analysis.invalidate()).catch(error => report(error, uri));
    }, 250));
  };
  const debugProvider: vscode.DebugConfigurationProvider = {
    provideDebugConfigurations: folder => folder && hasProject(folder.uri)
      ? synchronize()?.debugProvider.provideDebugConfigurations(folder) ?? [] : [],
    // null tells VS Code to cancel silently, rather than attempt another launch.
    resolveDebugConfiguration: (folder, config) => hasProject(folder?.uri ?? selectedUri())
      ? synchronize()?.debugProvider.resolveDebugConfiguration(folder, config) ?? null : null
  };
  const watcher = vscode.workspace.createFileSystemWatcher('**/*');
  context.subscriptions.push(
    watcher, watcher.onDidChange(changed), watcher.onDidCreate(changed), watcher.onDidDelete(changed),
    vscode.tasks.registerTaskProvider('recurloop', {
      provideTasks: () => synchronize()?.project.provideTasks() ?? [],
      resolveTask: task => typeof task.scope === 'object' && hasProject(task.scope.uri)
        ? synchronize()?.project.resolveTask(task) : undefined
    }),
    vscode.debug.registerDebugConfigurationProvider('recurloop', debugProvider, vscode.DebugConfigurationProviderTriggerKind.Dynamic),
    vscode.debug.registerDebugConfigurationProvider('recurloop', debugProvider),
    vscode.debug.registerDebugAdapterDescriptorFactory('recurloop', {
      createDebugAdapterDescriptor: session => hasProject(session.workspaceFolder?.uri ?? selectedUri())
        ? synchronize()?.debugFactory.createDebugAdapterDescriptor(session) : undefined
    }),
    vscode.window.registerTerminalProfileProvider('recurloop.console', {
      provideTerminalProfile: async () => {
        const uri = selectedUri();
        // A default terminal profile must still resolve in non-project folders.
        const shellProfile = () => new vscode.TerminalProfile({
          name: 'Terminal', shellPath: process.env.SHELL || '/bin/sh',
          cwd: uri ? vscode.workspace.getWorkspaceFolder(uri)?.uri.fsPath : undefined
        });
        if (!uri || !hasProject(uri)) return shellProfile();
        const active = synchronize();
        if (!active) return shellProfile();
        try { return new vscode.TerminalProfile(await active.runtime.terminalOptions(uri)); }
        catch (error) { if (!hasProject(uri)) return shellProfile(); throw error; }
      }
    }),
    vscode.commands.registerCommand('recurloop.initializeProject', async () => {
      const folders = vscode.workspace.workspaceFolders ?? [];
      const active = vscode.window.activeTextEditor?.document.uri;
      const folder = (active ? vscode.workspace.getWorkspaceFolder(active) : undefined)
        ?? (folders.length === 1 ? folders[0] : await vscode.window.showWorkspaceFolderPick());
      if (!folder) return;
      const entry = projectFile(folder.uri);
      try {
        fs.mkdirSync(path.dirname(entry), { recursive: true });
        try { fs.closeSync(fs.openSync(entry, 'wx')); }
        catch (error) { if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error; }
        const document = await vscode.workspace.openTextDocument(vscode.Uri.file(entry));
        await vscode.window.showTextDocument(document);
        changed(vscode.Uri.file(entry));
      } catch (error) { void vscode.window.showErrorMessage(String(error)); }
    }),
    vscode.commands.registerCommand('recurloop.runCurrentFile', () => inProject(active => runCurrentFile(active.prepareExecutable))),
    vscode.commands.registerCommand('recurloop.debugCurrentFile', () => inProject(() => debugCurrentFile())),
    vscode.commands.registerCommand('recurloop.openConsole', () => inProject(async (active, uri) => {
      vscode.window.createTerminal(await active.runtime.terminalOptions(uri)).show();
    })),
    vscode.commands.registerCommand('recurloop.installRuntime', () => inProject(async (active, uri) => {
      await active.setup.install(uri);
      for (const folder of vscode.workspace.workspaceFolders ?? []) await active.runtime.restart(folder.uri);
      active.analysis.invalidate();
    })),
    vscode.commands.registerCommand('recurloop.restartLanguageRuntime', () => inProject(async (active, uri) => {
      await active.runtime.restart(uri);
      active.analysis.invalidate();
      void vscode.window.showInformationMessage('RecurLoop language runtime restarted.');
    })),
    vscode.commands.registerCommand('recurloop.showRuntimeInfo', () => inProject((active, uri) => {
      active.output.appendLine(active.runtime.info(uri));
      active.output.show(true);
    })),
    vscode.workspace.onDidChangeConfiguration(event => {
      if (!event.affectsConfiguration('recurloop')) return;
      const active = synchronize();
      if (!active) return;
      for (const folder of vscode.workspace.workspaceFolders ?? []) {
        if (event.affectsConfiguration('recurloop', folder.uri)) {
          void active.runtime.restart(folder.uri).then(() => active.analysis.invalidate()).catch(error => report(error, folder.uri));
        }
      }
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      const active = synchronize();
      if (!active) return;
      // Drop sessions from folders that have been removed as well.
      void active.runtime.restart().then(async () => {
        for (const folder of vscode.workspace.workspaceFolders ?? []) {
          if (hasProject(folder.uri)) await active.runtime.restart(folder.uri);
        }
        active.analysis.invalidate();
      }).catch(error => active.output.appendLine(String(error)));
    }),
    { dispose: () => {
      for (const timer of pending.values()) clearTimeout(timer);
      features?.dispose();
      features = undefined;
    } }
  );
  const active = synchronize();
  if (active) for (const folder of vscode.workspace.workspaceFolders ?? []) {
    if (hasProject(folder.uri)) void active.runtime.restart(folder.uri).catch(error => report(error, folder.uri));
  }
}

async function runCurrentFile(prepareExecutable: (uri?: vscode.Uri) => Promise<string>): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== 'recurloop') {
    void vscode.window.showErrorMessage('Open a RecurLoop file first.');
    return;
  }
  if (editor.document.isDirty) await editor.document.save();
  const executable = await prepareExecutable(editor.document.uri);
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
