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

/** Identify owned versions without consulting executable settings or PATH. */
export function managedRuntimePrefixes(storage: string): string[] {
  storage = path.resolve(storage);
  const root = path.join(storage, 'runtime');
  if (!fs.existsSync(root) || fs.lstatSync(root).isSymbolicLink()) return [];
  const prefixes: string[] = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || !/^\d+\.\d+\.\d+$/.test(entry.name)) continue;
    const prefix = path.join(root, entry.name);
    const file = path.join(prefix, marker);
    if (!fs.existsSync(file) || fs.lstatSync(file).isSymbolicLink()) continue;
    const ownership = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (ownership.owner === owner && ownership.storage === storage) {
      prefixes.push(prefix);
    }
  }
  return prefixes;
}

/** The uninstall hook has no VS Code API; recorded paths also support scoped manual removal. */
export function removeManagedRuntimes(registry: string, onlyStorage?: string): void {
  const entries = readRegistry(registry);
  for (const storage of entries) {
    if (onlyStorage && storage !== path.resolve(onlyStorage)) continue;
    for (const prefix of managedRuntimePrefixes(storage)) fs.rmSync(prefix, { recursive: true, force: true });
  }
  const remaining = onlyStorage ? entries.filter(storage => storage !== path.resolve(onlyStorage)) : [];
  if (remaining.length) fs.writeFileSync(registry, JSON.stringify(remaining) + '\n');
  else fs.rmSync(registry, { force: true });
}
