import { test, expect } from '@playwright/test';
import { writeFile } from 'node:fs/promises';

test.beforeEach(async ({ page, baseURL }) => {
  await page.route('**/*', (route) => {
    if (new URL(route.request().url()).origin === baseURL) return route.continue();
    return route.abort('blockedbyclient');
  });
});
test.afterEach(async ({ page }, testInfo) => {
  if (page.isClosed()) return;
  await page.screenshot({ path: testInfo.outputPath(`${testInfo.status}.png`), fullPage: true });
  const events = await page.evaluate(() => window.demo?.events || []);
  await writeFile(testInfo.outputPath('events.json'), JSON.stringify(events, null, 2));
});
async function stats(page, request) {
  const thread = await page.evaluate(() => window.demo.threadId);
  return (await request.get(`/stats?thread=${thread}`, { headers: { 'X-Demo-Actor': 'alice' } })).json();
}
for (const backend of ['core', 'rails']) {
  test(`${backend}: real client streams two turns and reconnects without duplicate text`, async ({ page, request }) => {
    await page.goto(`/?backend=${backend}&scenario=text`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('success');
    await expect(page.getByRole('list', { name: 'Messages' })).toContainText('Hello from the offline Ruby host.');
    await page.getByLabel('Message', { exact: true }).fill('Another turn');
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('success');
    await expect(page.locator('#messages')).toContainText('Follow-up turn 2');
    const before = await page.locator('#messages').textContent();
    await page.getByRole('button', { name: 'Reconnect completed run' }).click();
    await expect(page.locator('#status')).toHaveText('reconnected: success');
    expect(await page.locator('#messages').textContent()).toBe(before);
    expect((await stats(page, request)).turns).toBe(2);
  });

  test(`${backend}: approval resumes the original tool once`, async ({ page, request }) => {
    await page.goto(`/?backend=${backend}`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('interrupt');
    expect((await stats(page, request)).effects).toBe(0);
    await page.getByRole('button', { name: 'Approve', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('success');
    await expect(page.locator('#tool')).toContainText('[redacted]');
    expect((await stats(page, request)).effects).toBe(1);
    const events = await page.evaluate(() => window.demo.events);
    expect(events.filter((e) => e.type === 'TOOL_CALL_START')).toHaveLength(1);
    expect(events.find((e) => e.type === 'TOOL_CALL_RESULT').toolCallId)
      .toBe(events.find((e) => e.type === 'TOOL_CALL_START').toolCallId);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('success');
    expect((await stats(page, request)).effects).toBe(1);
  });

  test(`${backend}: denial never executes the fixture tool on a mobile viewport`, async ({ page, request }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`/?backend=${backend}`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('interrupt');
    await page.getByRole('button', { name: 'Deny', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('success');
    await expect(page.locator('#messages')).toContainText('Order 42 was left alone.');
    expect((await stats(page, request)).effects).toBe(0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });

  test(`${backend}: failure is sanitized`, async ({ page }) => {
    await page.goto(`/?backend=${backend}&scenario=failure`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toContainText('error:');
    const events = await page.evaluate(() => window.demo.events);
    expect(events.at(-1).type).toBe('RUN_ERROR');
    expect(JSON.stringify(events)).not.toContain('fixture-secret');
  });

  test(`${backend}: cancellation is a cancelled outcome`, async ({ page }) => {
    await page.goto(`/?backend=${backend}&scenario=cancelled`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('cancelled');
  });
}
