---
layout: default
title: "Validating Input"
nav_order: 1
description: "Validate a bounded AG-UI request and turn it into immutable values."
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to parse a request body and inspect its typed values.
* How unknown members, size limits, and validation errors work.
* Which request values remain untrusted after parsing.

## Parse a Request

`RunAgentInput` arrives as JSON. Parse it before choosing a chat so malformed or oversized input is refused before provider work begins.

```ruby
require 'ruby_llm/ag_ui'

input = RubyLLM::AgUI::Input.parse({
  'threadId' => 'thread-1',
  'runId' => 'run-1',
  'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Hello' }]
})

puts [input.thread_id, input.run_id].join('/')
# => thread-1/run-1
```

`Input.parse` accepts a JSON string, a Hash, or a readable stream. The result is immutable. It exposes the accepted values, a canonical digest, and any non-fatal warnings.

## Unknown Members and Limits

By default, top-level members outside the pinned schema are stripped and recorded in `warnings`. Set `strict: true` to reject them. The parser also bounds the request body, nesting depth, and counts for messages, tools, and context.

```ruby
input = RubyLLM::AgUI::Input.parse({
  'threadId' => 'thread-1',
  'runId' => 'run-1',
  'messages' => [],
  'clientOnly' => true
})

input.warnings
# => ["stripped unknown RunAgentInput member \"clientOnly\""]
```

Pass `max_bytes:` to set a per-parse body limit. Configure `max_messages`, `max_tools`, and `max_context` on `RubyLLM::AgUI.config`. Invalid JSON, unsupported protocol versions, missing identifiers, and invalid message shapes raise an `InputError` subclass before a run starts.

## Parsed Data Does Not Grant Trust

The parser validates shape, not authority. Client-supplied tools are reported by `tool_names` and `client_tools?`, but they are never registered on the chat. The host chooses the model, tools, system prompt, chat history, and authenticated scope. Do not use `thread_id` or `run_id` as authorization by themselves.

## Next Steps

* [Getting Started]({% link _getting_started/getting-started.md %}) - install and parse a request.
* [Streaming Runs]({% link _core_features/streaming-runs.md %}) - pass a validated input to a RubyLLM chat.
* [Security and Deployment]({% link _advanced/security-and-deployment.md %}) - define the host trust boundary.
