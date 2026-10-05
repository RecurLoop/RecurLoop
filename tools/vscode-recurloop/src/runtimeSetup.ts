import { ChildProcess, execFile, spawn } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { configuredExecutable, findExecutable, hasProject, requireProject, resolveExecutable, setManagedExecutable } from './util';

function command(file: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(file, args, { timeout: 5000, maxBuffer: 65536, env: { ...process.env, NO_COLOR: '1' } }, (error, stdout, stderr) => {
      if (error) reject(new Error(`Cannot run '${file}': ${stderr.trim() || error.message}`));
      else resolve(stdout.trim());
    });
  });
}

/** Require the same protocol series, at least as recent as the bundled release. */
export function compatibleVersion(actual: string, required: string): boolean {
  const version = actual.match(/^Recurloop v(\d+)\.(\d+)\.(\d+)$/m);
  const expected = required.split('.').map(Number);
  return !!version && Number(version[1]) === expected[0] && Number(version[2]) === expected[1]
    && Number(version[3]) >= expected[2];
}

export class RuntimeSetup implements vscode.Disposable {
  private readonly version: string;
  private readonly prefix: string;
  private readonly binary: string;
  private readonly reported = new Set<string>();
  private pending?: Promise<string>;
  private installer?: ChildProcess;
  private deferred = false;
  private disposed = false;

  constructor(private readonly context: vscode.ExtensionContext, private readonly output: vscode.OutputChannel) {
    this.version = JSON.parse(fs.readFileSync(context.asAbsolutePath('out/runtime-release.json'), 'utf8')).version;
    if (!/^\d+\.\d+\.\d+$/.test(this.version)) throw new Error('Invalid bundled runtime version');
    this.prefix = path.join(context.globalStorageUri.fsPath, 'runtime', this.version);
    this.binary = path.join(this.prefix, 'bin', 'recurloop');
    setManagedExecutable(this.binary);
  }

  public async ensureExecutable(uri?: vscode.Uri, override?: string): Promise<string> {
    requireProject(uri);
    if (this.disposed) throw new Error('Runtime setup is disposed');
    try {
      const configured = configuredExecutable(uri, override);
      const executable = findExecutable(resolveExecutable(uri, override), uri);
      if (executable) return await this.validate(executable);
      if (configured !== 'recurloop' || override?.trim()) {
        throw new Error(`RecurLoop executable '${configured}' is missing or not executable. Fix recurloop.executablePath or the debug launch override; local builds are never substituted automatically.`);
      }
      if (this.deferred) throw new Error('RecurLoop setup was deferred. Use RecurLoop: Install Runtime or set recurloop.executablePath.');
      if (!this.pending) this.pending = this.requestSetup(uri);
      await this.pending;
      // A file picker may have changed the configuration while other workspaces waited.
      const selected = findExecutable(resolveExecutable(uri, override), uri);
      if (!selected) throw new Error('RecurLoop is still unavailable for this workspace. Set recurloop.executablePath.');
      return await this.validate(selected);
    } catch (error) {
      if (!hasProject(uri)) throw error;
      const message = error instanceof Error ? error.message : String(error);
      this.output.appendLine(`[setup] ${message}`);
      if (!message.includes('setup was deferred') && !this.reported.has(message) && !this.disposed) {
        this.reported.add(message);
        void vscode.window.showErrorMessage(message, 'Open Settings').then(choice => {
          if (choice === 'Open Settings') void vscode.commands.executeCommand('workbench.action.openSettings', 'recurloop.executablePath');
        });
      }
      throw error;
    }
  }

  public async install(uri?: vscode.Uri): Promise<void> {
    requireProject(uri);
    this.deferred = false;
    this.reported.clear();
    if (!this.pending) this.pending = this.requestSetup(uri);
    await this.pending;
  }

  private requestSetup(uri?: vscode.Uri): Promise<string> {
    return this.offerSetup(uri).catch(error => {
      // A failed download or invalid selection should not reopen dialogs on edits.
      this.deferred = true;
      throw error;
    }).finally(() => { this.pending = undefined; });
  }

  private async validate(executable: string): Promise<string> {
    // Probe on every selection: timestamps and size can stay unchanged when a
    // runtime is replaced, so file metadata cannot establish compatibility.
    const actual = await command(executable, ['--version']);
    if (!compatibleVersion(actual, this.version)) {
      throw new Error(`Incompatible RecurLoop runtime at '${executable}' (${actual}). This extension requires ${this.version} or a newer patch in the same major/minor series. Set recurloop.executablePath to a compatible executable.`);
    }
    return executable;
  }

  private async platformProblem(): Promise<string | undefined> {
    if (process.platform !== 'linux' || process.arch !== 'x64') return 'Automatic runtime installation currently supports Linux x86-64 only. In WSL, install the extension in the WSL workspace.';
    try {
      const libc = await command('getconf', ['GNU_LIBC_VERSION']);
      const match = libc.match(/^glibc (\d+)\.(\d+)$/);
      if (match && (Number(match[1]) > 2 || (Number(match[1]) === 2 && Number(match[2]) >= 35))) return undefined;
    } catch { /* no glibc */ }
    return 'Automatic runtime installation requires glibc >= 2.35. Musl/Alpine needs its own runtime build.';
  }

  private async offerSetup(uri?: vscode.Uri): Promise<string> {
    const problem = await this.platformProblem();
    const choices = problem ? ['Choose Executable', 'Later'] : ['Install', 'Choose Executable', 'Later'];
    const message = problem ?? `Install RecurLoop ${this.version} and its libraries from the official GitHub Release? Files will be stored in ${this.prefix} on ${vscode.env.remoteName ?? 'this machine'}. Administrator access and PATH changes are not required.`;
    const choice = await vscode.window.showInformationMessage(message, { modal: true }, ...choices);
    if (this.disposed) throw new Error('Runtime setup is disposed');
    requireProject(uri);
    if (choice === 'Choose Executable') {
      const files = await vscode.window.showOpenDialog({ canSelectMany: false, canSelectFiles: true, canSelectFolders: false, openLabel: 'Use RecurLoop executable' });
      if (files?.[0]) {
        requireProject(uri);
        const executable = await this.validate(files[0].fsPath);
        const target = uri && vscode.workspace.getWorkspaceFolder(uri) ? vscode.ConfigurationTarget.WorkspaceFolder : vscode.ConfigurationTarget.Global;
        await vscode.workspace.getConfiguration('recurloop', uri).update('executablePath', executable, target);
        return executable;
      }
    }
    if (choice !== 'Install') {
      this.deferred = true;
      throw new Error('RecurLoop setup was deferred. Use RecurLoop: Install Runtime to try again.');
    }
    return vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: `Installing RecurLoop ${this.version}` }, async () => {
      // Install to a fresh directory; failed downloads never become the active runtime.
      const parent = path.dirname(this.prefix);
      fs.mkdirSync(parent, { recursive: true });
      const staging = fs.mkdtempSync(path.join(parent, '.install-'));
      const backup = `${staging}.previous`;
      let backedUp = false;
      let promoted = false;
      try {
        await this.runInstaller(staging);
        const stagedBinary = path.join(staging, 'bin', 'recurloop');
        await this.validate(stagedBinary);
        if (this.disposed) throw new Error('Runtime setup is disposed');
        if (fs.existsSync(this.prefix)) { fs.renameSync(this.prefix, backup); backedUp = true; }
        try { fs.renameSync(staging, this.prefix); }
        catch (error) { if (backedUp) fs.renameSync(backup, this.prefix); throw error; }
        promoted = true;
        this.output.appendLine(`[setup] installed RecurLoop ${this.version} at ${this.prefix}`);
        void vscode.window.showInformationMessage(`RecurLoop ${this.version} is installed for this extension. Your terminal PATH is unchanged.`);
        return this.binary;
      } finally {
        fs.rmSync(staging, { recursive: true, force: true });
        if (promoted) fs.rmSync(backup, { recursive: true, force: true });
      }
    });
  }

  private runInstaller(prefix: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const child = spawn('sh', [this.context.asAbsolutePath('out/install-runtime.sh')], {
        cwd: path.dirname(prefix), detached: true, stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, RECURLOOP_VERSION: this.version, RECURLOOP_PREFIX: prefix }
      });
      this.installer = child;
      let tail = '';
      let timedOut = false;
      const log = (chunk: Buffer) => {
        tail = (tail + chunk.toString()).slice(-8000);
        this.output.append(chunk.toString());
      };
      child.stdout!.on('data', log);
      child.stderr!.on('data', log);
      const timer = setTimeout(() => { timedOut = true; this.stopInstaller(); }, 300000);
      child.once('error', error => { clearTimeout(timer); this.installer = undefined; reject(error); });
      child.once('close', code => {
        clearTimeout(timer);
        this.installer = undefined;
        if (code === 0 && !this.disposed && !timedOut) resolve();
        else reject(new Error(`RecurLoop installation failed${timedOut ? ' (timed out)' : ''}. ${tail.trim()}`));
      });
    });
  }

  private stopInstaller(): void {
    if (this.installer?.pid) {
      try { process.kill(-this.installer.pid, 'SIGTERM'); } catch { /* already stopped */ }
    }
  }

  public dispose(): void {
    this.disposed = true;
    this.stopInstaller();
    setManagedExecutable(undefined);
  }
}
