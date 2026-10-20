---
layout: default
title: Configuration
nav_order: 3
description: Set run storage, input limits, logging, and redaction defaults for the application.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to configure defaults once for the application.
* Which settings are available and what each one controls.

## Configuring RubyLLM AG-UI

```ruby
require 'ruby_llm/ag_ui'

RubyLLM::AgUI.configure do |config|
  config.run_store = RubyLLM::AgUI::Store::MemoryStore.new
  config.max_input_bytes = 256_000
  config.redact = RubyLLM::AgUI::Redaction.method(:default)
end

p RubyLLM::AgUI.config.to_h[:redact]
# => :default
```

## Settings

The global configuration supplies defaults. `Run.new` can override the store, logger, redaction policy, clock, interrupt expiry, and tool progress for one run. `MemoryStore` is process-local, so use a durable store when runs can move between workers.

| Setting | Default | Purpose |
| --- | --- | --- |
| `run_store` | `nil` | Store run records and interrupts. A run needs a store, supplied here or to `Run.new`. |
| `redact` | `Redaction.default` | Transform tool results before they reach the stream. |
| `emit_tool_progress` | `false` | Publish tool progress as redacted activity snapshots. |
| `logger` | `nil` | Receive host-side diagnostics without prompts or raw tool payloads. |
| `protocol_version` | `"1.0"` | Fixed supported version reported by `RUN_STARTED`; setting another value raises `ConfigurationError`. |
| `max_input_bytes` | `256_000` | Maximum request body size. |
| `max_messages` | `500` | Maximum messages in one request. |
| `max_tools` | `64` | Maximum tool definitions in one request. |
| `max_context` | `64` | Maximum context entries in one request. |
| `interrupt_ttl` | `900` seconds | How long an approval interrupt can be answered. |
| `clock` | `Time.now.utc` | Clock used to set interrupt expiry. |

`Configuration#protocol_version=` accepts only `"1.0"`. Its value describes the
producer; it does not select another event schema.

Client history stays under host control. There is no configuration switch that
trusts or imports it into a chat.

Provider keys and model selection are configured through RubyLLM and the host app. This gem does not read credentials when it loads.

## Next Steps

* [Getting Started]({% link _getting_started/getting-started.md %}) - install and parse a request.
* [How RubyLLM AG-UI Works]({% link _getting_started/overview.md %}) - the parts of one run.
* [Security and Deployment]({% link _advanced/security-and-deployment.md %}) - host responsibilities and safe defaults.
