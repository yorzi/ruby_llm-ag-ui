# ruby_llm-ag_ui

[![CI](https://github.com/yorzi/ruby_llm-ag-ui/actions/workflows/ci.yml/badge.svg)](https://github.com/yorzi/ruby_llm-ag-ui/actions/workflows/ci.yml)

Run [RubyLLM](https://rubyllm.com) 2.x chats as [AG-UI](https://github.com/ag-ui-protocol/ag-ui) 1.0 agent runs.

`ruby_llm-ag_ui` turns one RubyLLM chat turn into one AG-UI run: it validates the
inbound `RunAgentInput`, maps RubyLLM streaming, tool and lifecycle behavior onto
schema-valid AG-UI events, turns `requires_approval` pauses into interrupt
outcomes with host-authorized resume, reports `Chat#cancel` as the cancelled
outcome, and writes the stream as Server-Sent Events. A pure-Ruby core comes
with an optional Rails adapter.

> **Unofficial community project.** This gem is not affiliated with, endorsed
> by, or maintained by the RubyLLM maintainers or the AG-UI protocol
> maintainers. `RubyLLM::` and "AG-UI" appear here because this gem extends
> those projects, not because it speaks for them.

## Why

If your agent already runs on RubyLLM and you want an AG-UI client (CopilotKit,
`@ag-ui/client`, or another AG-UI consumer) in front of it, you currently have
to hand-map RubyLLM callbacks, approval pauses and cancellation onto the AG-UI
run lifecycle, and you have to parse and authorize `RunAgentInput` yourself —
the community Ruby SDK builds outbound events but has no inbound parser. The
usual results are wrong terminal events, duplicate runs on retry, approvals that
are not bound to the call they approve, and cancellations reported as success.
This gem removes that mapping work.

## What it does and does not do

It owns the RubyLLM → AG-UI mapping, input parsing, event ordering, run identity
and terminal correctness. It is **not** an AG-UI core SDK, a schema fork, a chat
UI, a CopilotKit runtime clone, or a second agent framework. RubyLLM owns the
agent loop, tool execution, approval pauses and cancellation checkpoints. Your
application owns identity, authorization, which tools and model a run may use,
and persistence.

## Status

Pre-release (`0.1.0`). The pure-Ruby core, run store, approval/resume, cancel
handling and the Rails adapter are implemented and covered by an offline test
suite. Compatibility claims for real AG-UI clients and live providers are
tracked in [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) and are
**not** asserted until recorded there.

See [docs/](docs) for the architecture, the protocol coverage map, the
compatibility matrix and the security model.

## Installation

```ruby
# Gemfile
gem 'ruby_llm-ag_ui'
```

```bash
bundle install
```

Requires Ruby >= 3.2, RubyLLM >= 2.1 and `ag-ui-protocol` ~> 0.2.0.

## Quick start (pure Ruby)

The host authenticates, authorizes and builds the chat; the gem writes the
stream.

```ruby
require 'ruby_llm'
require 'ruby_llm/ag_ui'

input = RubyLLM::AgUI::Input.parse(request_body)   # bounds, validates, digests
chat  = host_chat_for(actor, input.thread_id)     # your RubyLLM::Chat

RubyLLM::AgUI::Run.new(
  chat: chat,
  input: input,
  scope: "tenant:#{tenant.id}:actor:#{actor.id}", # from authenticated identity
  store: run_store
).stream(to: sse_io)
```

`scope` is what the run is reserved under: it must be a non-empty String the host
builds from authenticated identity, never anything from the request body.

`examples/pure_ruby/app.rb` is a runnable Rack endpoint that streams a complete
run — a tool call, an approval pause and the run that answers it — with no
provider and no credentials (`rake example`, or
`rackup examples/pure_ruby/config.ru`). Set `RUBY_LLM_AG_UI_EXAMPLE_MODEL` to
drive a real `RubyLLM::Chat` through the same code.

## Rails

The optional adapter provides a controller concern, a durable run store keyed
by the actor's scope, and reconnect snapshots. It loads only when
`Rails::Railtie` is already defined.

```ruby
class AgentRunsController < ApplicationController
  include RubyLLM::AgUI::Rails::Streaming

  def create
    stream_ag_ui_run { |input| current_user.chats.find_or_create_by!(ag_ui_thread_id: input.thread_id) }
  end

  def ag_ui_scope
    "actor:#{current_user.id}"
  end
end
```

See [docs/RAILS.md](docs/RAILS.md) and `examples/rails_8`.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
rake example        # prints a full AG-UI run as SSE
```

The suite is offline: fakes instead of a provider, no network, no credentials.
The only test that talks to a model is opt-in:

```bash
RUBY_LLM_LIVE=1 OPENAI_API_KEY=... bundle exec rspec spec/live
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — the components, the run, the invariants.
- [Protocol coverage](docs/PROTOCOL_COVERAGE.md) — all 31 AG-UI 1.0 event types
  and what this gem does with each.
- [Compatibility](docs/COMPATIBILITY.md) — what is asserted and what is not.
- [Rails](docs/RAILS.md) — the controller concern, the store, resume, transport.
- [Security](docs/SECURITY.md) — the threat model and the deployment checklist.
- [Upstream issue drafts](docs/upstream/ag-ui-protocol-0.2.0.md) — the five gaps
  in `ag-ui-protocol` 0.2.0 this gem works around.

## License

MIT. See [LICENSE.txt](LICENSE.txt). Third-party notices are in
[docs/LICENSES.md](docs/LICENSES.md).

This is an unofficial community project and is not affiliated with the RubyLLM or
AG-UI maintainers. Report security issues privately — see [SECURITY.md](SECURITY.md).
