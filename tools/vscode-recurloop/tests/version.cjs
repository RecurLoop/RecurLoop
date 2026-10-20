const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { syncVersion } = require('../../sync-version.cjs');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rl-version-'));
const extension = path.join(root, 'tools/vscode-recurloop');
try {
  fs.mkdirSync(extension, { recursive: true });
  fs.writeFileSync(path.join(root, 'CMakeLists.txt'), 'project(RecurLoop\n VERSION 1.2.3 LANGUAGES C CXX)\n');
  fs.writeFileSync(path.join(extension, 'package.json'), JSON.stringify({ name: 'test', version: '0.0.1' }));
  fs.writeFileSync(path.join(extension, 'package-lock.json'), JSON.stringify({ version: '0.0.1', packages: {
    '': { version: '0.0.1' }, 'node_modules/dependency': { version: '9.8.7' }
  } }));
  assert.throws(() => syncVersion(root, { check: true }), /out of sync/);
  assert.throws(() => syncVersion(root, { tag: 'v1.2.2' }), /must match/);
  assert.equal(require(path.join(extension, 'package.json')).version, '0.0.1');
  assert.equal(syncVersion(root, { tag: 'v1.2.3' }), '1.2.3');
  assert.equal(JSON.parse(fs.readFileSync(path.join(extension, 'package.json'))).version, '1.2.3');
  const lock = JSON.parse(fs.readFileSync(path.join(extension, 'package-lock.json')));
  assert.equal(lock.version, '1.2.3');
  assert.equal(lock.packages[''].version, '1.2.3');
  assert.equal(lock.packages['node_modules/dependency'].version, '9.8.7');
  assert.equal(syncVersion(root, { check: true }), '1.2.3');
  assert.equal(syncVersion(root, { tag: 'v1.2.3' }), '1.2.3');
  fs.writeFileSync(path.join(root, 'CMakeLists.txt'), 'project(RecurLoop LANGUAGES C CXX)\n');
  assert.throws(() => syncVersion(root), /Cannot determine/);
  console.log('Version synchronization passed: canonical source, manifests, tag mismatch and dependency preservation.');
} finally { fs.rmSync(root, { recursive: true, force: true }); }
