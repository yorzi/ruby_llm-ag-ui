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

  test(`${backend}: approval resumes the original tool once`, async ({ page, request }, testInfo) => {
    await page.goto(`/?backend=${backend}`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('interrupt');
    expect((await stats(page, request)).effects).toBe(0);
    await page.getByRole('button', { name: 'Approve', exact: true }).click();
    await expect(page.locator('#progress')).toContainText('"value":1');
    await expect(page.locator('#status')).toHaveText('running');
    await page.screenshot({ path: testInfo.outputPath('progress-running.png'), fullPage: true });
    await expect(page.locator('#status')).toHaveText('success');
    await expect(page.locator('#tool')).toContainText('[redacted]');
    expect((await stats(page, request)).effects).toBe(1);
    await expect(page.locator('#progress')).toContainText('"value":3');
    const events = await page.evaluate(() => window.demo.events);
    expect(events.filter((e) => e.type === 'TOOL_CALL_START')).toHaveLength(1);
    const progress = events.filter((e) => e.type === 'ACTIVITY_SNAPSHOT');
    expect(progress).toHaveLength(2);
    expect(progress[0].messageId).toBe(progress[1].messageId);
    expect(progress.every((e) => e.replace && e.activityType === 'TOOL_PROGRESS')).toBe(true);
    expect(JSON.stringify(events)).not.toContain('fixture-secret');
    expect(events.find((e) => e.type === 'TOOL_CALL_RESULT').toolCallId)
      .toBe(events.find((e) => e.type === 'TOOL_CALL_START').toolCallId);
    const originalCall = events.find((e) => e.type === 'TOOL_CALL_START').toolCallId;
    const messages = await page.evaluate(() => window.demo.messages);
    expect(messages.flatMap((m) => m.toolCalls || []).filter((c) => c.id === originalCall)).toHaveLength(1);
    expect(messages.filter((m) => m.role === 'tool' && m.toolCallId === originalCall)).toHaveLength(1);
    const visibleBeforeReplay = await page.locator('#messages').textContent();
    await page.getByRole('button', { name: 'Reconnect completed run' }).click();
    await expect(page.locator('#status')).toHaveText('reconnected: success');
    expect(await page.locator('#messages').textContent()).toBe(visibleBeforeReplay);
    expect((await stats(page, request)).effects).toBe(1);
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

  test(`${backend}: an interrupt blocks another turn and a new conversation restores controls`, async ({ page }) => {
    await page.goto(`/?backend=${backend}`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('interrupt');
    await expect(page.getByRole('button', { name: 'Run turn', exact: true })).toBeDisabled();
    const before = await page.evaluate(() => window.demo.threadId);
    await page.getByRole('button', { name: 'New conversation' }).click();
    await expect(page.locator('#status')).toHaveText('idle');
    await expect(page.getByRole('button', { name: 'Run turn', exact: true })).toBeEnabled();
    expect(await page.evaluate(() => window.demo.threadId)).not.toBe(before);
    await page.getByLabel('Scenario', { exact: true }).selectOption('text');
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('success');
  });

  test(`${backend}: active host cancellation is scoped to the exact run`, async ({ page, request }, testInfo) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`/?backend=${backend}`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('interrupt');
    await page.getByRole('button', { name: 'Approve', exact: true }).click();
    await expect(page.locator('#progress')).toContainText('"value":1');
    const input = await page.evaluate(() => window.demo.input);
    const payload = { threadId: input.threadId, runId: input.runId, messages: [] };
    const otherActor = await request.post('/cancel', { data: payload, headers: { 'X-Demo-Actor': 'bob' } });
    expect(otherActor.status()).toBe(404);
    const otherRun = await request.post('/cancel', { data: { ...payload, runId: 'old-run' },
      headers: { 'X-Demo-Actor': 'alice' } });
    expect(otherRun.status()).toBe(404);
    await page.getByRole('button', { name: 'Cancel server run', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('cancelled');
    await page.screenshot({ path: testInfo.outputPath('cancelled.png'), fullPage: true });
    expect((await stats(page, request)).effects).toBe(0);
    await page.getByRole('button', { name: 'Reconnect completed run' }).click();
    await expect(page.locator('#status')).toHaveText('reconnected: cancelled');
    const inactive = await request.post('/cancel', { data: payload, headers: { 'X-Demo-Actor': 'alice' } });
    expect(inactive.status()).toBe(409);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('success');
    expect((await stats(page, request)).effects).toBe(0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });

  test(`${backend}: HTTP abort leaves the producer running and reconnect never repeats its tool`, async ({ page, request }, testInfo) => {
    await page.goto(`/?backend=${backend}`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('interrupt');
    await page.getByRole('button', { name: 'Approve', exact: true }).click();
    await expect(page.locator('#progress')).toContainText('"value":1');
    const input = await page.evaluate(() => window.demo.input);
    const duplicate = await request.post(`/${backend === 'rails' ? 'agent' : 'core'}`, { data: input,
      headers: { 'Accept': 'text/event-stream', 'X-Demo-Actor': 'alice', 'X-Demo-Scenario': 'approval' } });
    expect(duplicate.status()).toBe(409);
    await page.getByRole('button', { name: 'Disconnect stream', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('disconnected');
    await page.screenshot({ path: testInfo.outputPath('disconnected.png'), fullPage: true });
    await expect.poll(async () => (await stats(page, request)).status).toBe('succeeded');
    expect((await stats(page, request)).effects).toBe(1);
    await page.getByRole('button', { name: 'Reconnect completed run' }).click();
    await expect(page.locator('#status')).toHaveText('reconnected: success');
    expect((await stats(page, request)).effects).toBe(1);
    expect((await stats(page, request)).turns).toBe(2);
  });

  test(`${backend}: timeout is a sanitized failure`, async ({ page }) => {
    await page.goto(`/?backend=${backend}&scenario=timeout`);
    await page.getByRole('button', { name: 'Run turn', exact: true }).click();
    await expect(page.locator('#status')).toHaveText('error: transport_timeout');
    await page.getByRole('button', { name: 'Reconnect completed run' }).click();
    await expect(page.locator('#status')).toHaveText('error: transport_timeout');
    expect(JSON.stringify(await page.evaluate(() => window.demo.events))).not.toContain('fixture-secret');
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
