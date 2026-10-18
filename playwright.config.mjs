import { defineConfig } from '@playwright/test';
import { existsSync } from 'node:fs';
if (!process.env.BROWSER_ARTIFACTS) throw new Error('Use bin/check-browser for disposable browser checks');
const localChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath = process.env.CHROME_BIN || (existsSync(localChrome) ? localChrome : undefined);
const port = Number(process.env.PORT || 3199);
export default defineConfig({
  testDir: './spec/browser',
  timeout: 15000,
  workers: 1,
  retries: 0,
  outputDir: `${process.env.BROWSER_ARTIFACTS}/results`,
  reporter: [['list']],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    viewport: { width: 1280, height: 900 },
    launchOptions: { executablePath },
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'bundle exec ruby examples/client/server.rb',
    url: `http://127.0.0.1:${port}/health`,
    timeout: 30000,
    reuseExistingServer: false,
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5000 },
  },
});
