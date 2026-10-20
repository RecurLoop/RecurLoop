const assert = require('node:assert/strict');
const Module = require('node:module');
const reports = [];
let active = 0;
const vscode = {
  StatusBarAlignment: { Left: 1 },
  window: { createStatusBarItem: () => ({
    set text(value) { reports.push(value); },
    show() { assert.equal(this.command, 'recurloop.showProcessingLog'); active++; },
    dispose() { active--; }
  }) }
};
const original = Module._load;
Module._load = function(name, ...rest) { return name === 'vscode' ? vscode : original.call(this, name, ...rest); };
const { runtimeProgress } = require('../out/progress');
const log = [];
const progress = runtimeProgress({ appendLine: line => log.push(line) });
(async () => {
  const uri = { fsPath: '/workspace/project' };
  assert.equal(await progress(uri, 'Loading', async report => {
    assert.equal(active, 1);
    report('2/4 stages complete; 2 remaining');
    return 42;
  }), 42);
  assert.equal(active, 0);
  assert.ok(reports.some(message => message.includes('2/4 stages complete; 2 remaining')));
  assert.ok(log.some(line => line.includes('[/workspace/project] Loading: ready')));
  await assert.rejects(progress(uri, 'Reloading', async () => { throw new Error('broken source'); }), /broken source/);
  assert.equal(active, 0);
  assert.ok(log.some(line => line.includes('Reloading: failed: Error: broken source')));
  console.log('Progress passed: visible activity, clickable logs, completion and failure cleanup.');
})().catch(error => { console.error(error); process.exitCode = 1; });
