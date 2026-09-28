const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

const wrapper = path.resolve(__dirname, '../bin/claude');
const container = 'claudecode-00000000';

// Run the real wrapper with fake Podman and Claude processes to exercise
// startup ordering, argument boundaries, failures, and container cleanup.
function run(args, overrides = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-wrapper-'));
  const home = path.join(dir, 'home');
  fs.mkdirSync(home);
  const log = path.join(dir, 'calls.jsonl');
  const mock = path.join(dir, 'mock.cjs');
  fs.writeFileSync(mock, `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const tool = path.basename(process.argv[1]);
const args = process.argv.slice(2);
if (tool === 'uuidgen') {
  console.log('00000000-0000-0000-0000-000000000000');
  process.exit(0);
}
fs.appendFileSync(process.env.WRAPPER_TEST_LOG, JSON.stringify({tool, args}) + '\\n');
if (tool === 'claude') {
  if (process.env.MOCK_REMOTE_EXIT) {
    console.error('Remote startup failed');
    process.exit(Number(process.env.MOCK_REMOTE_EXIT));
  }
  process.exit(Number(process.env.MOCK_SESSION_EXIT || 0));
}
if (args[0] === 'run') {
  console.log('test-container-id');
  process.exit(Number(process.env.MOCK_RUN_EXIT || 0));
}
if (args[0] === 'cp') process.exit(Number(process.env.MOCK_CP_EXIT || 0));
if (args[0] === 'stop') process.exit(Number(process.env.MOCK_STOP_EXIT || 0));
if (args[0] === 'exec') {
  const command = args.slice(args.indexOf('${container}') + 1);
  if (command[0] === 'claude') {
    const result = spawnSync(command[0], command.slice(1), {stdio: 'inherit'});
    process.exit(result.status ?? 1);
  }
  process.exit(Number(process.env.MOCK_INIT_EXIT || 0));
}
`, { mode: 0o755 });
  for (const tool of ['podman', 'claude', 'uuidgen']) {
    fs.symlinkSync(mock, path.join(dir, tool));
  }
  try {
    const result = spawnSync('bash', [wrapper, ...args], {
      encoding: 'utf8',
      timeout: 10000,
      env: {
        ...process.env,
        PATH: `${dir}:${process.env.PATH}`,
        HOME: home,
        WRAPPER_TEST_LOG: log,
        ...overrides,
      },
    });
    assert.ifError(result.error);
    const calls = fs.existsSync(log)
      ? fs.readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse)
      : [];
    const config = path.join(home, '.claude.json');
    const configText = fs.existsSync(config) ? fs.readFileSync(config, 'utf8') : null;
    return { ...result, calls, configText };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const claudeCalls = result => result.calls.filter(call => call.tool === 'claude');
const stopped = result => result.calls.filter(call => call.tool === 'podman' && call.args[0] === 'stop');

test('remote mode starts an interactive session, preserves arguments, and cleans up', () => {
  const args = ['--model', 'example-model', '--append-system-prompt', 'notice="two words"', 'Explain "this"\n$(false) *'];
  const result = run(['--local', '--remote', ...args]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.calls[0].args.slice(-4), ['--entrypoint', '/bin/sleep', 'claude-code:latest', 'infinity']);
  assert.deepEqual(claudeCalls(result).map(call => call.args), [
    ['--remote-control', path.basename(process.cwd()), ...args],
  ]);
  assert.deepEqual(stopped(result).map(call => call.args), [['stop', container]]);
  assert.ok(!result.calls.some(call => call.args.includes('attach')));
});

test('initialization finishes before remote startup', () => {
  const result = run(['--remote', '--apk-packages', 'jq,curl', '--init-script', 'root init.sh', '--init-script-claude', 'user init.sh', '--continue']);
  assert.equal(result.status, 0, result.stderr);
  const commands = result.calls.filter(call => call.tool === 'podman' && call.args[0] === 'exec');
  assert.deepEqual(commands.map(call => call.args.slice(call.args.indexOf(container) + 1, call.args.indexOf(container) + 2)), [
    ['/bin/bash'], ['bash'], ['bash'], ['claude'],
  ]);
  assert.deepEqual(claudeCalls(result)[0].args.slice(-1), ['--continue']);
});

test('remote command failure is visible and cleans up', () => {
  const result = run(['--remote'], { MOCK_REMOTE_EXIT: '23' });
  assert.equal(result.status, 23);
  assert.match(result.stderr, /Remote startup failed/);
  assert.equal(claudeCalls(result).length, 1);
  assert.equal(stopped(result).length, 1);
  assert.ok(!result.calls.some(call => call.args.includes('attach')));
});

test('session exit status survives container cleanup', () => {
  const result = run(['--remote'], { MOCK_SESSION_EXIT: '42', MOCK_STOP_EXIT: '99' });
  assert.equal(result.status, 42);
  assert.equal(stopped(result).length, 1);
});

test('container creation failure skips exec, attach, and stop', () => {
  const result = run(['--remote'], { MOCK_RUN_EXIT: '125' });
  assert.equal(result.status, 125);
  assert.equal(result.calls.length, 1);
});

test('initialization failure skips remote startup and cleans up', () => {
  const result = run(['--remote', '--init-script', 'init.sh'], { MOCK_INIT_EXIT: '19' });
  assert.equal(result.status, 19);
  assert.equal(claudeCalls(result).length, 0);
  assert.equal(stopped(result).length, 1);
});

test('ordinary mode keeps the image entrypoint and attaches', () => {
  const result = run(['--local', 'a prompt with spaces']);
  assert.equal(result.status, 0);
  assert.deepEqual(result.calls[0].args.slice(-2), ['claude-code:latest', 'a prompt with spaces']);
  assert.ok(!result.calls[0].args.includes('--entrypoint'));
  assert.deepEqual(result.calls[1].args, ['container', 'attach', container]);
  assert.equal(stopped(result).length, 0);
});

test('ordinary initialization failure also cleans up its container', () => {
  const result = run(['--init-script', 'init.sh'], { MOCK_INIT_EXIT: '19' });
  assert.equal(result.status, 19);
  assert.equal(stopped(result).length, 1);
  assert.ok(!result.calls.some(call => call.args.includes('attach')));
});

test('separator forwards the native Claude cloud-session flag unchanged', () => {
  const result = run(['--local', '--', '--remote', 'Fix the login bug']);
  assert.equal(result.status, 0);
  assert.deepEqual(result.calls[0].args.slice(-3), ['claude-code:latest', '--remote', 'Fix the login bug']);
  assert.ok(!result.calls[0].args.includes('--entrypoint'));
});

test('help documents remote mode without starting a container', () => {
  const result = run(['--help']);
  assert.equal(result.status, 0);
  assert.match(result.stdout, /--remote\s+Start an interactive session/);
  assert.equal(result.calls.length, 0);
});

for (const option of ['--init-script', '--init-script-claude', '--apk-packages', '--podman-arg']) {
  test(option + ' rejects a missing value without launching a container', () => {
    const result = run([option]);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /Missing value/);
    assert.equal(result.calls.length, 0);
  });
}

test('copy failure skips Claude startup and cleans up', () => {
  const result = run(['--remote', '--init-script', 'init.sh'], { MOCK_CP_EXIT: '17' });
  assert.equal(result.status, 17);
  assert.equal(claudeCalls(result).length, 0);
  assert.equal(stopped(result).length, 1);
});

test('a fresh home gets a JSON configuration before container startup', () => {
  const result = run(['--remote']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.configText), {});
});

test('native Remote Control server command is forwarded unchanged', () => {
  const result = run(['--local', 'remote-control', '--name', 'My Project']);
  assert.equal(result.status, 0);
  assert.deepEqual(result.calls[0].args.slice(-4), ['claude-code:latest', 'remote-control', '--name', 'My Project']);
});

test('Podman long options remain supported', () => {
  const result = run(['--remote', '--podman-arg', '--network=host']);
  assert.equal(result.status, 0);
  assert.ok(result.calls[0].args.includes('--network=host'));
});
