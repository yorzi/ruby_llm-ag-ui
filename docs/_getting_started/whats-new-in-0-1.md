---
layout: default
title: "What's New in 0.1"
nav_order: 0
description: Use the first RubyLLM AG-UI release to stream, resume, cancel, and reconnect agent runs.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to install version 0.1.
* Which run lifecycle features it provides.
* Which compatibility checks still need a real application.

## Install the First Release

```ruby
gem 'ruby_llm-ag_ui', '~> 0.1.0'
```

Use Ruby 3.2 or later, RubyLLM 2.1 or later within version 2, and `ag-ui-protocol` 0.2. Follow [Getting Started]({% link _getting_started/getting-started.md %}) to create your first run.

## Stream One Chat Turn as One Run

The gem validates `RunAgentInput` and maps RubyLLM text, tool, and lifecycle callbacks to AG-UI events. An SSE writer sends each encoded event to the client. See [Streaming Runs]({% link _core_features/streaming-runs.md %}) and [Protocol Coverage]({% link _reference/protocol-coverage.md %}).

## Pause, Resume, Cancel, and Reconnect

Tool approval pauses use interrupts bound to their tool calls. Your host authorizes the actor and records the decision before resuming. Cancellation produces the cancelled outcome. A retry for a completed run replays its recorded state and terminal event. See [Approval and Resume]({% link _core_features/approval-and-resume.md %}) and [Reconnects]({% link _core_features/reconnects.md %}).

## Add the Optional Rails Adapter

The adapter supplies a streaming controller concern, an ActiveRecord run store, and an installation generator. The pure-Ruby entrypoint does not load Rails. Follow [Rails Integration]({% link _advanced/rails-integration.md %}).

## Check Your Application's Compatibility

Offline checks cover the mapping, schema, lifecycle, store, and adapter behavior. A release does not establish interoperability with every AG-UI client or live provider. Read [Compatibility]({% link _reference/compatibility.md %}) and record your application checks before making those claims.
