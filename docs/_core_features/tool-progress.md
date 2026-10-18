---
layout: default
title: Tool Progress
nav_order: 5
description: Publish local tool progress as redacted AG-UI activity snapshots.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to enable tool progress globally or for one run.
* How progress snapshots identify a tool call and replace earlier values.
* How to choose which progress values reach the client.

## Enable Progress

Long tools can report their work before the result arrives. Enable progress
when your client handles AG-UI activity messages:

```ruby
RubyLLM::AgUI.configure do |config|
  config.emit_tool_progress = true
end
```

The default is `false`. You can override it on one run with
`Run.new(chat: chat, input: input, scope: scope, store: store,
emit_tool_progress: true)`. Set the per-run option to `false` to disable a global
opt-in. The Rails concern uses the global setting.

The gem listens to RubyLLM's `after_tool_progress(tool_call, progress)` callback.
Your RubyLLM tool reports progress through its own `progress` method. The gem
publishes only values that the tool reports; it does not estimate a percentage
or make up a total.

## Choose a Redaction Policy

Progress can include private messages. Its values pass through the configured
redactor with kind `:tool_progress`. The default replaces each reported value
with `[redacted]`, including numeric values. The tool call identifier remains
available so the client can associate the activity with the existing call.

For example, a host can publish counts while withholding messages:

```ruby
RubyLLM::AgUI.configure do |config|
  config.emit_tool_progress = true
  config.redact = lambda do |kind, payload|
    if kind == :tool_progress
      payload.slice('value', 'total')
    else
      RubyLLM::AgUI::Redaction.default(kind, payload)
    end
  end
end
```

Use `Redaction.method(:none)` only for host-approved public data. The same
policy still protects tool results with kind `:tool_result`.

## Read an Activity Snapshot

With counts approved by the host, a tool update can produce:

```json
{"type":"ACTIVITY_SNAPSHOT","messageId":"run-1:progress:call-1","activityType":"TOOL_PROGRESS","content":{"toolCallId":"call-1","progress":{"value":1,"total":3}},"replace":true}
```

Each tool call has one activity id per run. Later updates replace that
activity's content. Unknown fields are absent: a message-only update has no
`value` or `total`. Empty progress updates produce no event.

Snapshots do not open another tool call, change an approval, or determine the
run outcome. Updates for a tool whose result has arrived are ignored, as are
callbacks after the run closes. Concurrent callbacks and run finalization use
the same lock so progress cannot be written after the terminal event.

Progress is not retained for reconnect. A completed-run reconnect serves its
recorded outcome and optional state snapshot, without replaying activity,
text, or tool deltas. No `ACTIVITY_DELTA` events are produced.

## Next Steps

* [Client Example]({% link _advanced/client-example.md %}) - try a real client with offline tools.
* [Configuration]({% link _getting_started/configuration.md %}) - choose run defaults.
* [Protocol Coverage]({% link _reference/protocol-coverage.md %}) - inspect supported events.
