import { spawn } from 'node:child_process';
import { mkdir, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
const artifacts = path.resolve(`tmp/browser/${new Date().toISOString().replaceAll(/[:.]/g, '-')}-${process.pid}`);
await mkdir(artifacts, { recursive: true });
const pidFile = path.join(artifacts, 'server.pid');
console.log(`Browser artifacts: ${artifacts}`);
function run(command, args, env = process.env) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { env, stdio: 'inherit' });
    child.on('error', reject);
    child.on('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`${command}: ${signal || code}`)));
  });
}
try {
  await run('node', ['scripts/build-demo.mjs']);
  await run('node', ['node_modules/@playwright/test/cli.js', 'test'], {
    ...process.env, BROWSER_ARTIFACTS: artifacts, DEMO_PID_FILE: pidFile,
  });
  await run('bundle', ['exec', 'ruby', 'scripts/check_browser_events.rb', artifacts]);
} catch (error) {
  console.error(`${error.message}; inspect ${artifacts}`);
  process.exitCode = 1;
} finally {
  // The pid belongs to this run's allowlisted demo. Playwright normally stops it.
  try {
    const pid = Number(await readFile(pidFile, 'utf8'));
    try { process.kill(pid, 'SIGTERM'); } catch (error) { if (error.code !== 'ESRCH') throw error; }
    await rm(pidFile, { force: true });
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
}
