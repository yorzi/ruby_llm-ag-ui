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

The global configuration supplies defaults. `Run.new` can override the store, logger, redaction policy, clock, and interrupt expiry for one run. `MemoryStore` is process-local, so use a durable store when runs can move between workers.

| Setting | Default | Purpose |
| --- | --- | --- |
| `run_store` | `nil` | Store run records and interrupts. A run needs a store, supplied here or to `Run.new`. |
| `redact` | `Redaction.default` | Transform tool results before they reach the stream. |
| `logger` | `nil` | Receive host-side diagnostics without prompts or raw tool payloads. |
| `protocol_version` | `"1.0"` | Value reported by `RUN_STARTED`. |
| `max_input_bytes` | `256_000` | Maximum request body size. |
| `max_messages` | `500` | Maximum messages in one request. |
| `max_tools` | `64` | Maximum tool definitions in one request. |
| `max_context` | `64` | Maximum context entries in one request. |
| `interrupt_ttl` | `900` seconds | How long an approval interrupt can be answered. |
| `clock` | `Time.now.utc` | Clock used to set interrupt expiry. |
| `allow_client_history` | `false` | Reserved for future history behavior; client history is not trusted in this release. |

Provider keys and model selection are configured through RubyLLM and the host app. This gem does not read credentials when it loads.

## Next Steps

* [Getting Started]({% link _getting_started/getting-started.md %}) - install and parse a request.
* [How RubyLLM AG-UI Works]({% link _getting_started/overview.md %}) - the parts of one run.
* [Security and Deployment]({% link _advanced/security-and-deployment.md %}) - host responsibilities and safe defaults.
