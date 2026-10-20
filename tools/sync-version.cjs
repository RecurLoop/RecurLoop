// CMakeLists.txt owns the release version. Other manifests are derived copies.
const fs = require('node:fs');
const path = require('node:path');

function syncVersion(root, { check = false, tag } = {}) {
  const cmake = fs.readFileSync(path.join(root, 'CMakeLists.txt'), 'utf8');
  const version = cmake.match(/project\(RecurLoop\s+VERSION\s+(\d+\.\d+\.\d+)\b/)?.[1];
  if (!version) throw new Error('Cannot determine the RecurLoop release version from CMakeLists.txt');
  if (tag !== undefined && tag !== `v${version}`)
    throw new Error(`Release tag ${tag} must match v${version} from CMakeLists.txt`);

  const extension = path.join(root, 'tools/vscode-recurloop');
  for (const filename of ['package.json', 'package-lock.json']) {
    const file = path.join(extension, filename);
    const original = fs.readFileSync(file, 'utf8');
    const manifest = JSON.parse(original);
    const stale = manifest.version !== version || (filename === 'package-lock.json' && manifest.packages[''].version !== version);
    if (check && stale) throw new Error(`${filename} is out of sync; run node tools/sync-version.cjs`);
    if (stale) {
      manifest.version = version;
      if (filename === 'package-lock.json') manifest.packages[''].version = version;
      fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + '\n');
    }
  }
  return version;
}

module.exports = { syncVersion };
if (require.main === module) {
  const args = process.argv.slice(2);
  const options = {};
  while (args.length) {
    const arg = args.shift();
    if (arg === '--check') options.check = true;
    else if (arg === '--tag' && args.length) options.tag = args.shift();
    else throw new Error(`Unexpected argument ${arg}; use --check and/or --tag vX.Y.Z`);
  }
  console.log(syncVersion(path.resolve(__dirname, '..'), options));
}
