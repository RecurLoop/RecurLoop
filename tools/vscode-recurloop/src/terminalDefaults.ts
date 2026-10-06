import * as vscode from 'vscode';
import { hasProject } from './util';

const profileName = 'RecurLoop';
const profile = { extensionIdentifier: 'recurloop.recurloop-vscode', id: 'recurloop.console', title: profileName };

interface SavedDefaults {
  defaultProfile?: string | null;
  profile?: unknown;
  hadProfiles: boolean;
  installed: boolean;
}

/** Select the project console without changing defaults outside this workspace. */
export class TerminalDefaults {
  private pending: Promise<void> = Promise.resolve();
  private readonly platform = process.platform === 'win32' ? 'windows' : process.platform === 'darwin' ? 'osx' : 'linux';
  private readonly stateKey = `recurloop.defaultTerminal.${this.platform}`;

  constructor(private readonly state: vscode.Memento) {}

  synchronize(): Promise<void> {
    // File and configuration events can overlap while settings writes are pending.
    const next = this.pending.then(() => this.apply());
    this.pending = next.catch(() => {});
    return next;
  }

  private async apply(): Promise<void> {
    const enabled = (vscode.workspace.workspaceFolders ?? []).some(folder => hasProject(folder.uri));
    const config = vscode.workspace.getConfiguration('terminal.integrated');
    const defaultsKey = `defaultProfile.${this.platform}`;
    const profilesKey = `profiles.${this.platform}`;
    const saved = this.state.get<SavedDefaults>(this.stateKey);
    const defaults = config.inspect<string | null>(defaultsKey)?.workspaceValue;
    const profiles = config.inspect<Record<string, unknown>>(profilesKey)?.workspaceValue;

    if (enabled) {
      // Once selected, allow the user to choose another terminal without fighting it.
      if (saved?.installed) return;
      const original = saved ?? { defaultProfile: defaults, profile: profiles?.[profileName], hadProfiles: profiles !== undefined, installed: false };
      await this.state.update(this.stateKey, original);
      await config.update(profilesKey, { ...profiles, [profileName]: profile }, vscode.ConfigurationTarget.Workspace);
      await config.update(defaultsKey, profileName, vscode.ConfigurationTarget.Workspace);
      await this.state.update(this.stateKey, { ...original, installed: true });
      return;
    }

    if (!saved) return;
    // Restore only settings that still belong to us; retain later user edits.
    if (defaults === profileName) await config.update(defaultsKey, saved.defaultProfile, vscode.ConfigurationTarget.Workspace);
    const current = profiles?.[profileName] as Partial<typeof profile> | undefined;
    if (current && Object.keys(current).length === Object.keys(profile).length
      && current.extensionIdentifier === profile.extensionIdentifier && current.id === profile.id && current.title === profile.title) {
      const restored = { ...profiles };
      if (saved.profile === undefined) delete restored[profileName];
      else restored[profileName] = saved.profile;
      await config.update(profilesKey, !saved.hadProfiles && !Object.keys(restored).length ? undefined : restored, vscode.ConfigurationTarget.Workspace);
    }
    await this.state.update(this.stateKey, undefined);
  }
}
