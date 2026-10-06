import * as fs from 'fs';
import * as path from 'path';

const owner = 'recurloop.recurloop-vscode';
const marker = '.extension-managed.json';

function readRegistry(file: string): string[] {
  if (!fs.existsSync(file)) return [];
  const entries: unknown = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!Array.isArray(entries) || !entries.every(entry => typeof entry === 'string' && path.isAbsolute(entry))) {
    throw new Error('Invalid managed runtime registry');
  }
  return entries;
}

/** Register only release packages in the extension's own storage, including older versions. */
export function registerManagedRuntimes(storage: string, registry: string): void {
  const root = path.join(storage, 'runtime');
  if (!fs.existsSync(root) || fs.lstatSync(root).isSymbolicLink()) return;
  let found = false;
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || !/^\d+\.\d+\.\d+$/.test(entry.name)) continue;
    const prefix = path.join(root, entry.name);
    if (!fs.existsSync(path.join(prefix, 'bin/recurloop'))
      || !fs.existsSync(path.join(prefix, 'share/recurloop/PACKAGE-MANIFEST.sha256'))) continue;
    fs.writeFileSync(path.join(prefix, marker), JSON.stringify({ owner, storage: path.resolve(storage) }) + '\n');
    found = true;
  }
  if (!found) return;
  const entries = new Set(readRegistry(registry));
  entries.add(path.resolve(storage));
  fs.writeFileSync(registry, JSON.stringify([...entries]) + '\n');
}

/** The uninstall hook has no VS Code API; use recorded storage paths, never executable settings or PATH. */
export function removeManagedRuntimes(registry: string): void {
  for (const storage of readRegistry(registry)) {
    const root = path.join(storage, 'runtime');
    if (!fs.existsSync(root) || fs.lstatSync(root).isSymbolicLink()) continue;
    for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
      if (!entry.isDirectory() || !/^\d+\.\d+\.\d+$/.test(entry.name)) continue;
      const prefix = path.join(root, entry.name);
      const file = path.join(prefix, marker);
      if (!fs.existsSync(file) || fs.lstatSync(file).isSymbolicLink()) continue;
      const ownership = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (ownership.owner === owner && ownership.storage === storage) {
        fs.rmSync(prefix, { recursive: true, force: true });
      }
    }
  }
  fs.rmSync(registry, { force: true });
}
