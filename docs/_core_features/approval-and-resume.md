---
layout: default
title: "Approval and Resume"
nav_order: 3
description: "Pause a run for host-authorized tool approval and answer the interrupt on a new run."
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* What an approval interrupt contains.
* How the client answers it on a new run.
* What the host must authorize again before a tool executes.

## Return an Interrupt

When RubyLLM pauses on `requires_approval`, the run ends with an interrupt outcome. The interrupt identifies the pending tool call and includes a host-owned expiry. The id and expiry below are from a sample run; each run receives new values.

```json
{
  "type": "RUN_FINISHED",
  "threadId": "thread-1",
  "runId": "run-1",
  "outcome": {
    "type": "interrupt",
    "interrupts": [{
      "id": "817cc7a4-c2b4-4393-a25b-09819cf7198a",
      "reason": "tool_call_confirmation",
      "message": "Approve the cancel_order tool call?",
      "toolCallId": "call_cancel_42",
      "expiresAt": "2026-10-18T02:19:38Z"
    }]
  }
}
```

The interrupt does not expose the tool arguments digest used by the server. A client cannot use the response as a permission token.

## Answer on a New Run

The client sends a new `runId` for the same thread and includes a resume entry. `resolved` approves the pending call; `cancelled` records a denial.

```json
{
  "threadId": "thread-1",
  "runId": "run-2",
  "messages": [{ "id": "m1", "role": "user", "content": "Cancel order 42." }],
  "resume": [{ "interruptId": "817cc7a4-c2b4-4393-a25b-09819cf7198a", "status": "resolved" }]
}
```

The interrupt must still be pending and unexpired. The tool call id and argument digest must match the call RubyLLM is holding. The host must re-authorize the action before the tool executes. The store records only one decision, so a replay cannot execute the tool twice.

## Next Steps

* [Streaming Runs]({% link _core_features/streaming-runs.md %}) - follow the event and outcome sequence.
* [Reconnects and Run Identity]({% link _core_features/reconnects.md %}) - understand stored run identity.
* [Security and Deployment]({% link _advanced/security-and-deployment.md %}) - keep approval separate from authorization.


## Keep the Original Tool Call

RubyLLM fires its before-tool callback when an approved call executes. The
resume run does not repeat the original `TOOL_CALL_START`, arguments, or end.
Its `TOOL_CALL_RESULT` uses the original `toolCallId`. A later new tool call
still emits its own start and arguments. Keep the client conversation across
both runs so the result can attach to the call shown before the interrupt.
