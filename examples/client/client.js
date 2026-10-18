import { HttpAgent } from '@ag-ui/client';

const byId = (id) => document.getElementById(id);
const query = new URLSearchParams(location.search);
for (const name of ['backend', 'actor', 'scenario']) {
  if ([...byId(name).options].some((o) => o.value === query.get(name))) byId(name).value = query.get(name);
}
const settings = () => Object.fromEntries(['backend', 'actor', 'scenario'].map((n) => [n, byId(n).value]));
let agent, threadId, interrupts = [], lastInput, busy = false;
const events = [];
const status = (text) => { byId('status').textContent = text; };
function render(messages) {
  byId('messages').replaceChildren(...messages.filter((m) => m.content && m.role !== 'activity').map((m) => {
    const item = document.createElement('li');
    item.textContent = `${m.role}: ${typeof m.content === 'string' ? m.content : JSON.stringify(m.content)}`;
    return item;
  }));
}
function subscriber(replay = false) {
  return {
    onEvent({ event }) {
      events.push(event);
      byId('events').textContent = events.map((e) => JSON.stringify(e)).join('\n');
    },
    onMessagesChanged({ messages }) { if (!replay) render(messages); },
    onRunFinishedEvent({ outcome, interrupts: pending = [] }) {
      interrupts = pending;
      status(replay ? `reconnected: ${outcome}` : outcome);
      byId('approval').hidden = pending.length === 0;
    },
    onRunErrorEvent({ event }) { status(`error: ${event.code}`); },
    onToolCallResultEvent({ event }) { byId('tool').textContent = `Tool result: ${event.content}`; },
    onActivitySnapshotEvent({ event }) {
      byId('progress').textContent = `Tool progress: ${JSON.stringify(event.content)}`;
    },
  };
}
function createAgent(initialMessages = [], initialState = {}) {
  const { backend, actor, scenario } = settings();
  return new HttpAgent({
    url: `${location.origin}/${backend === 'rails' ? 'agent' : 'core'}`,
    threadId, initialMessages, initialState,
    headers: { 'X-Demo-Actor': actor, 'X-Demo-Scenario': scenario },
    fetch(url, init) {
      lastInput = JSON.parse(init.body);
      return fetch(url, init);
    },
  });
}
function reset() {
  threadId = crypto.randomUUID();
  agent = createAgent();
  interrupts = []; lastInput = undefined; events.length = 0;
  render([]); status('idle');
  byId('approval').hidden = true;
  byId('reconnect').disabled = true;
  for (const name of ['events', 'tool', 'progress']) byId(name).textContent = '';
}
async function execute(resume) {
  if (busy) return;
  busy = true; status('running'); byId('run').disabled = true;
  try {
    if (!resume) agent.addMessage({ id: crypto.randomUUID(), role: 'user', content: byId('prompt').value });
    await agent.runAgent({ runId: crypto.randomUUID(), ...(resume ? { resume } : {}) }, subscriber());
    byId('reconnect').disabled = interrupts.length > 0;
  } catch (error) {
    status(`error: ${error.message}`);
  } finally { busy = false; byId('run').disabled = false; }
}
byId('turn').addEventListener('submit', (event) => { event.preventDefault(); execute(); });
byId('approve').onclick = () => execute(interrupts.map((i) => ({ interruptId: i.id, status: 'resolved' })));
byId('deny').onclick = () => execute(interrupts.map((i) => ({ interruptId: i.id, status: 'cancelled' })));
byId('reset').onclick = reset;
for (const name of ['backend', 'actor', 'scenario']) byId(name).onchange = reset;
byId('reconnect').onclick = async () => {
  if (busy || !lastInput) return;
  busy = true;
  const input = structuredClone(lastInput);
  try {
    const replay = createAgent(input.messages, input.state);
    await replay.runAgent({ runId: input.runId, tools: input.tools, context: input.context,
      forwardedProps: input.forwardedProps, resume: input.resume }, subscriber(true));
  } catch (error) { status(`error: ${error.message}`); }
  finally { busy = false; }
};
window.demo = { get events() { return events; }, get threadId() { return threadId; }, get input() { return lastInput; } };
reset();
