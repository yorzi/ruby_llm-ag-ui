---
layout: default
title: "Streaming Runs"
nav_order: 2
description: "Run one RubyLLM chat turn and write ordered AG-UI events as server-sent events."
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to connect a host-owned chat, parsed input, scope, and store.
* How a RubyLLM turn becomes ordered AG-UI events.
* What each terminal outcome means.

## Run a Complete Example

The repository includes a scripted chat that emits an approval pause, resumes the tool call, and prints the server-sent events. Run it from the repository root; it does not need a provider key.

```sh
bundle exec rake example
```

In an application, parse the request first, then pass the host-selected chat, parsed input, authenticated scope, and run store to `RubyLLM::AgUI::Run`. Call `stream(to:)` with an IO-like stream. The host builds the chat and authorizes access to the thread; the gem reserves the run identity before provider work.

## Event Order

The mapper turns RubyLLM callbacks into AG-UI events. The emitter assigns each event a sequence, persists run state, closes open text or tool events, and writes one JSON event per `data:` line through the SSE writer.

An assistant message opens on its first non-empty chunk and closes before a tool call, phase change, or terminal event. A tool call starts when its id and name are known, emits the arguments as received, and ends before the call runs. One run ends with one terminal result.

## Outcomes

* A completed chat ends with `RUN_FINISHED` and a `success` outcome.
* A `requires_approval` pause ends with `RUN_FINISHED` and an `interrupt` outcome.
* `Chat#cancel` ends with `RUN_FINISHED` and a `cancelled` outcome.
* A failure ends with `RUN_ERROR` and a sanitized message and code.
* A pause the protocol cannot express is an error, never a success.

The run record reaches a terminal state before the terminal event is written. If the connection closes in the middle, the record remains available for a later reconnect.

## When the Client Disconnects

The producer detaches a failed transport and continues the same chat turn while
its worker stays alive. A broken connection does not cancel the provider or
undo a tool. The store retains the real success, failure, approval pause, or
cancelled outcome. A retry while the turn is running is refused; after it ends,
the same input and run id receive the recorded outcome without execution.

This also applies when the first write or a flush fails. A terminal write
failure cannot replace an outcome that is already persisted. `SSEWriter` used
directly raises `TransportError`, a subclass of `StreamError`; `Run` handles
that transport error. Mapping and persistence errors are separate failures.

## Next Steps

* [Validating Input]({% link _core_features/input-validation.md %}) - parse untrusted request data.
* [Tool Progress]({% link _core_features/tool-progress.md %}) - publish local tool updates.
* [Approval and Resume]({% link _core_features/approval-and-resume.md %}) - answer an interrupt on a new run.
* [Reconnects and Run Identity]({% link _core_features/reconnects.md %}) - serve a completed run again.
