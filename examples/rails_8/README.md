# A Rails 8 AG-UI endpoint

The app-specific part of serving a RubyLLM chat as an AG-UI run from Rails: the
controller, the models, the route, the initializer and the two migrations. The
gem ships the rest — the input parser, the mapper, the SSE writer, the run store
and the `Rails::Streaming` concern.

This directory is not a whole Rails application. Create one, install both
generators, then copy these files over it.

## Run it

```bash
rails new agent_demo --skip-javascript --skip-hotwire --skip-action-mailer --skip-action-mailbox
cd agent_demo

# RubyLLM 2.x and its chat/message/tool-call tables.
bundle add ruby_llm
bin/rails g ruby_llm:install
bin/rails g ruby_llm:ag_ui:install

# This example: the actor, the thread→chat mapping, the endpoint.
cp -R ../ruby_llm-ag_ui/examples/rails_8/app/* app/
cp -R ../ruby_llm-ag_ui/examples/rails_8/config/initializers/* config/initializers/
cp ../ruby_llm-ag_ui/examples/rails_8/config/routes.rb config/routes.rb
cp ../ruby_llm-ag_ui/examples/rails_8/db/migrate/* db/migrate/

bundle add ruby_llm-ag_ui --path ../ruby_llm-ag_ui
bin/rails db:prepare
bin/rails server
```

Then POST a `RunAgentInput` and read the events back:

```bash
curl -N http://localhost:3000/agent \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -H 'X-Actor: demo' \
  -d '{
        "threadId": "thread-1",
        "runId": "run-1",
        "messages": [{"id": "m1", "role": "user", "content": "Hello"}]
      }'
```

`-N` matters: without it `curl` buffers, and an event stream that arrives all at
once is not an event stream. Every `data:` line is one AG-UI event; the last one
is `RUN_FINISHED`.

## What it shows

- **Failure before the first event.** No `X-Actor` header is a 401. An `Accept`
  that cannot read an event stream is a 406. A body past `config.max_input_bytes`
  is a 413. A run id already used with different input is a 409. The gem decides
  each of those before the response is committed, so a client that cannot be
  served gets a status instead of half a run.
- **A scope built from the actor.** `ag_ui_scope` is
  `"actor:#{actor.id}"`, read from the authenticated request and never from the
  body. It bounds every reservation, so two actors using the same `threadId`
  cannot reach each other's runs.
- **A threadId that is the host's to interpret.** The controller maps `threadId`
  to a chat through the actor's own association. A client-supplied id never
  selects a record directly.
- **A durable store.** `Rails::ActiveRecordStore` keeps run identity in
  `ruby_llm_ag_ui_runs`, which is what makes a retried request attach instead of
  executing twice.
- **An approval pause that is not a success.** A tool declared with
  `requires_approval` ends the run as `RUN_FINISHED` with an interrupt outcome.
  The client answers it with `resume: [{interruptId: ..., status: "resolved"}]`
  on a new run; the tool executes once, and a replayed answer is refused.
- **Reconnect.** The same `(threadId, runId)` with the same input replays the
  run's terminal event and its `STATE_SNAPSHOT` instead of running the chat
  again.

## What this example does not do

It has not been booted against a live model in this repository: the adapter's
specs cover the request path with a controller double, and the pure-Ruby example
in `examples/pure_ruby` covers the event stream end to end. Running it here needs
a provider key, so the remaining check is yours:

- replace `ScriptedChat`-free `Chat` with a `requires_approval` tool and confirm
  the interrupt/resume round trip against your provider;
- confirm with `curl -N` that the events arrive progressively rather than in one
  chunk at the end (a buffering proxy or a missing `X-Accel-Buffering` will show
  up as exactly that).

Concurrency is the other thing to decide before production: `ActionController::Live`
holds a thread for the length of the run, and a web server with a handful of
workers will run out of them before it runs out of requests. See
`docs/_advanced/rails-integration.md` for the job-backed transport.
