// Exercise setup with real processes and the bundled installer; downloads use local fixtures.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const { execFileSync } = require('node:child_process');
const extension = path.resolve(__dirname, '..');
const version = require('../out/runtime-release.json').version;
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-setup fixture-'));
const originalPath = process.env.PATH;
const tools = path.join(root, 'tools');
fs.mkdirSync(tools);
const folder = { uri: { fsPath: path.join(root, 'workspace') } };
fs.mkdirSync(folder.uri.fsPath);
let setting;
let choice = 'Later';
let selectedFile;
let prompts = 0;
const messages = [];
const opened = [];
let updates = 0;
const errors = [];
const vscode = {
  env: { remoteName: 'wsl', openExternal: async uri => opened.push(uri) },
  Uri: { parse: value => value }, ConfigurationTarget: { WorkspaceFolder: 3, Global: 1 },
  ProgressLocation: { Notification: 15 },
  workspace: {
    workspaceFolders: [folder], getWorkspaceFolder: () => folder,
    getConfiguration: () => ({
      get: (key, fallback) => key === 'executablePath' ? setting : fallback,
      update: async (key, value, target) => {
        assert.equal(key, 'executablePath'); assert.equal(target, 3);
        setting = value; updates++;
      }
    })
  },
  window: {
    showInformationMessage: async (message, options, ...items) => {
      if (!options?.modal) return;
      prompts++;
      messages.push(message);
      assert.ok(items.includes('Later'));
      return choice;
    },
    showErrorMessage: async message => { errors.push(message); },
    showOpenDialog: async () => selectedFile ? [{ fsPath: selectedFile }] : undefined,
    withProgress: async (_options, task) => task()
  }, commands: { executeCommand: async () => {} }
};
const originalLoad = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : originalLoad.call(this, name, ...rest); };
const { RuntimeSetup, compatibleVersion } = require('../out/runtimeSetup');
const { resolveExecutable, configuredExecutable } = require('../out/util');
const { removeManagedRuntimes } = require('../out/runtimeOwnership');
const extensionFixture = path.join(root, 'extension');
fs.mkdirSync(path.join(extensionFixture, 'out'), { recursive: true });
fs.copyFileSync(path.join(extension, 'out/runtime-release.json'), path.join(extensionFixture, 'out/runtime-release.json'));
fs.copyFileSync(path.join(extension, 'out/install-runtime.sh'), path.join(extensionFixture, 'out/install-runtime.sh'));
const registry = path.join(extensionFixture, 'out/managed-runtimes.json');
const output = { appendLine() {}, append() {} };
let setup;
function create(storage) {
  setup?.dispose();
  const context = { globalStorageUri: { fsPath: path.join(root, storage) }, asAbsolutePath: relative => path.join(extensionFixture, relative) };
  setup = new RuntimeSetup(context, output);
  return path.join(context.globalStorageUri.fsPath, 'runtime', version);
}
function binary(file, runtimeVersion = version) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `#!/bin/sh\nprintf '%s\\n' 'Recurloop v${runtimeVersion}'\n`, { mode: 0o755 });
  return file;
}
function fixture(corruptManifest = false) {
  const name = `recurloop-${version}-linux-x86_64`;
  const staging = path.join(root, 'package', name);
  const binaryPath = binary(path.join(staging, 'bin/recurloop'));
  const entries = ['bin/recurloop'];
  for (const library of ['language-kit', 'shell', 'inferred', 'http', 'gui', 'ide', 'project', 'embed']) {
    const relative = `share/recurloop/libraries/${library}.rli`;
    const file = path.join(staging, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, `fixture ${library}\n`);
    entries.push(relative);
  }
  const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  fs.writeFileSync(path.join(staging, 'share/recurloop/PACKAGE-MANIFEST.sha256'),
    entries.map(entry => `${sha(path.join(staging, entry))}  ${entry}\n`).join(''));
  if (corruptManifest) fs.appendFileSync(path.join(staging, 'share/recurloop/libraries/ide.rli'), 'tampered\n');
  const archive = path.join(root, `${name}.tar.gz`);
  execFileSync('tar', ['-czf', archive, '-C', path.dirname(staging), name]);
  fs.writeFileSync(`${archive}.sha256`, `${sha(archive)}  ${path.basename(archive)}\n`);
  fs.writeFileSync(`${archive}.bad`, `${'0'.repeat(64)}  ${path.basename(archive)}\n`);
  process.env.RECURLOOP_FIXTURE_ARCHIVE = archive;
  fs.writeFileSync(path.join(tools, 'curl'), `#!/bin/sh
set -eu
destination=''
url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) destination="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  *.sha256)
    if [ "\${RECURLOOP_BAD_CHECKSUM:-}" = 1 ]; then
      cp "$RECURLOOP_FIXTURE_ARCHIVE.bad" "$destination"
    else
      cp "$RECURLOOP_FIXTURE_ARCHIVE.sha256" "$destination"
    fi ;;
  *.tar.gz) cp "$RECURLOOP_FIXTURE_ARCHIVE" "$destination" ;;
  *) exit 1 ;;
esac
`, { mode: 0o755 });
  return binaryPath;
}

(async () => {
  process.env.PATH = `${tools}:/usr/bin:/bin`;
  const packagedDefault = require('../package.json').contributes.configuration.properties['recurloop.executablePath'].default;
  assert.equal(packagedDefault, 'recurloop');
  assert.equal(configuredExecutable(folder.uri), 'recurloop');
  binary(path.join(folder.uri.fsPath, 'build/Release/bin/recurloop'));
  assert.equal(resolveExecutable(folder.uri), 'recurloop'); // public default never searches local builds
  assert.ok(compatibleVersion(`Recurloop v${version}`, version));
  assert.ok(!compatibleVersion('Recurloop v0.1.0', version));
  assert.ok(!compatibleVersion('different program', version));

  let prefix = create('deferred');
  await assert.rejects(setup.ensureExecutable(folder.uri), /saved project entry/);
  await assert.rejects(setup.install(folder.uri), /saved project entry/);
  assert.equal(prompts, 0); // no setup or version probe before opting in
  fs.writeFileSync(path.join(folder.uri.fsPath, 'recurloop.project.rl'), '');
  await assert.rejects(setup.ensureExecutable(folder.uri), /deferred/);
  assert.equal(prompts, 1);
  assert.ok(!fs.existsSync(prefix));
  await assert.rejects(setup.ensureExecutable(folder.uri), /deferred/);
  assert.equal(prompts, 1); // no repeated automatic prompt
  assert.ok(messages[0].includes('globally and add it to PATH'));
  assert.ok(messages[0].includes('https://github.com/RecurLoop/RecurLoop#install-the-latest-release'));
  choice = 'Installation Guide';
  await assert.rejects(setup.install(folder.uri), /deferred/);
  assert.deepEqual(opened, ['https://github.com/RecurLoop/RecurLoop#install-the-latest-release']);

  // Explicit paths stay explicit even when another local build exists.
  setting = '${workspaceFolder}/missing/recurloop';
  assert.equal(resolveExecutable(folder.uri), path.join(folder.uri.fsPath, 'missing/recurloop'));
  await assert.rejects(setup.ensureExecutable(folder.uri), /missing or not executable/);
  assert.equal(prompts, 2);
  setting = '${workspaceFolder}/build/Release/bin/recurloop';
  assert.equal(await setup.ensureExecutable(folder.uri), path.join(folder.uri.fsPath, 'build/Release/bin/recurloop'));
  await assert.rejects(setup.ensureExecutable(folder.uri, '/missing/debug-override'), /debug launch override/);

  selectedFile = fixture();
  choice = 'Choose Executable';
  await setup.install(folder.uri);
  assert.equal(setting, selectedFile);
  assert.equal(updates, 1);
  assert.equal(await setup.ensureExecutable(folder.uri), selectedFile);

  setting = undefined;
  choice = 'Install';
  prefix = create('managed');
  const before = prompts;
  const results = await Promise.all([setup.ensureExecutable(folder.uri), setup.ensureExecutable(folder.uri)]);
  const managedBinary = path.join(prefix, 'bin/recurloop');
  assert.deepEqual(results, [managedBinary, managedBinary]);
  assert.equal(prompts, before + 1);
  assert.equal(updates, 1); // managed installation never changes settings
  assert.equal(process.env.PATH, `${tools}:/usr/bin:/bin`);
  assert.ok(fs.existsSync(path.join(prefix, 'share/recurloop/libraries/ide.rli')));
  create('managed'); // rediscover on a subsequent extension activation
  assert.equal(await setup.ensureExecutable(folder.uri), managedBinary);
  assert.equal(prompts, before + 1);

  const onPath = binary(path.join(tools, 'recurloop'));
  assert.equal(await setup.ensureExecutable(folder.uri), onPath); // PATH has priority over managed runtime
  binary(onPath, '0.1.0');
  await assert.rejects(setup.ensureExecutable(folder.uri), /Incompatible/);
  assert.equal(prompts, before + 1); // a broken PATH runtime is never replaced silently
  fs.unlinkSync(onPath);
  setting = '/missing/explicit';
  await assert.rejects(setup.ensureExecutable(folder.uri), /missing or not executable/);
  setting = undefined;

  // The bundled real installer must reject a corrupt checksum before publishing.
  process.env.RECURLOOP_BAD_CHECKSUM = '1';
  prefix = create('bad-checksum');
  await assert.rejects(setup.ensureExecutable(folder.uri), /checksum verification failed/);
  assert.ok(!fs.existsSync(prefix));
  assert.deepEqual(fs.readdirSync(path.dirname(prefix)), []);
  const afterFailure = prompts;
  await assert.rejects(setup.ensureExecutable(folder.uri), /deferred/);
  assert.equal(prompts, afterFailure);
  delete process.env.RECURLOOP_BAD_CHECKSUM;
  await setup.install(folder.uri); // a failed download can be retried explicitly
  assert.equal(await setup.ensureExecutable(folder.uri), path.join(prefix, 'bin/recurloop'));

  fixture(true); // valid outer checksum, invalid internal manifest
  await assert.rejects(setup.install(folder.uri), /checksum|did NOT match/);
  assert.equal(fs.readFileSync(path.join(prefix, 'share/recurloop/libraries/ide.rli'), 'utf8'), 'fixture ide\n');
  assert.equal(await setup.ensureExecutable(folder.uri), path.join(prefix, 'bin/recurloop'));

  const platformProblem = setup.platformProblem.bind(setup);
  setup.platformProblem = async () => 'Unsupported test platform';
  choice = 'Later';
  await assert.rejects(setup.install(folder.uri), /deferred/);
  setup.platformProblem = platformProblem;
  assert.ok(errors.some(message => message.includes('Incompatible')));
  setup.dispose();
  assert.ok(fs.existsSync(managedBinary)); // disable/reload must preserve installations
  const older = path.join(root, 'managed/runtime/0.0.1');
  fs.cpSync(path.dirname(path.dirname(managedBinary)), older, { recursive: true });
  fs.unlinkSync(path.join(older, '.extension-managed.json')); // migrate a pre-hook installation
  create('managed');
  const external = binary(path.join(root, 'external/bin/recurloop'));
  setting = external;
  assert.equal(await setup.ensureExecutable(folder.uri), external);
  const unowned = binary(path.join(root, 'managed/runtime/9.9.9/bin/recurloop'));
  const symlink = path.join(root, 'managed/runtime/8.8.8');
  fs.symlinkSync(path.dirname(path.dirname(external)), symlink);
  for (const file of ['uninstall.js', 'runtimeOwnership.js']) {
    fs.copyFileSync(path.join(extension, 'out', file), path.join(extensionFixture, 'out', file));
  }
  assert.equal(require('../package.json').scripts['vscode:uninstall'], 'node ./out/uninstall.js');
  execFileSync(process.execPath, [path.join(extensionFixture, 'out/uninstall.js')]);
  assert.ok(!fs.existsSync(managedBinary));
  assert.ok(!fs.existsSync(older));
  assert.ok(!fs.existsSync(prefix)); // also removes other registered storage locations
  assert.ok(fs.existsSync(external));
  assert.ok(fs.existsSync(unowned));
  assert.ok(fs.lstatSync(symlink).isSymbolicLink());
  removeManagedRuntimes(registry); // idempotent without a registry or managed runtime
  console.log('Runtime setup passed: defaults, explicit paths, consent, picker, concurrent setup, verified install, rediscovery, PATH precedence, compatibility and failed-download recovery.');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  setup?.dispose();
  process.env.PATH = originalPath;
  delete process.env.RECURLOOP_FIXTURE_ARCHIVE;
  delete process.env.RECURLOOP_BAD_CHECKSUM;
  fs.rmSync(root, { recursive: true, force: true });
});
