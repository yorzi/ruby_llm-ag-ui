# ruby_llm-ag_ui

[![CI](https://github.com/yorzi/ruby_llm-ag_ui/actions/workflows/ci.yml/badge.svg)](https://github.com/yorzi/ruby_llm-ag_ui/actions/workflows/ci.yml)

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

See [docs/](docs) for the architecture, the protocol coverage map and the
compatibility matrix.

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

input = RubyLLM::AgUI::Input.parse(request_body, max_bytes: 256_000)
chat  = host_chat_for(actor, input.thread_id) # your RubyLLM::Chat

RubyLLM::AgUI::Run.new(chat: chat, input: input, actor: actor, store: run_store)
                   .stream(to: sse_io)
```

`examples/pure_ruby/app.rb` is a runnable Rack endpoint that streams a complete
run, including a tool call and an approval pause, against a fake provider.

## Rails

The optional adapter provides a controller concern, a thread mapping for
`acts_as_chat` records, a run store and reconnect snapshots. See
[docs/RAILS.md](docs/RAILS.md) and `examples/rails_8`.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
rake example        # prints a full AG-UI run as SSE
```

## License

MIT. See [LICENSE.txt](LICENSE.txt). Third-party notices are in
[docs/LICENSES.md](docs/LICENSES.md).
