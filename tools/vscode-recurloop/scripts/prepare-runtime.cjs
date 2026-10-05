// Bundle the maintained release installer and pin its version to this source tree.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const out = path.resolve(__dirname, '../out');
const cmake = fs.readFileSync(path.join(root, 'CMakeLists.txt'), 'utf8');
const version = cmake.match(/project\(RecurLoop VERSION (\d+\.\d+\.\d+)\b/)?.[1];
if (!version) throw new Error('Cannot determine the RecurLoop release version');
fs.mkdirSync(out, { recursive: true });
fs.copyFileSync(path.join(root, 'tools/install.sh'), path.join(out, 'install-runtime.sh'));
fs.writeFileSync(path.join(out, 'runtime-release.json'), JSON.stringify({ version }) + '\n');
