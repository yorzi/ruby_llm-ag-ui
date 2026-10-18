---
layout: default
title: "Reconnects and Run Identity"
nav_order: 4
description: "Reserve each run once and report its recorded outcome after a reconnect."
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How the gem reserves `(scope, threadId, runId)` for one input digest.
* How retries and reconnects differ from duplicate execution.
* Which store to use for one process or several workers.

## Reuse a Run Identity

The store reserves a run before any provider work. It keys the record by authenticated scope, thread id, and run id, then compares the canonical digest of the accepted input.

| Request | Result |
| --- | --- |
| New identity | Reserve and execute the run. |
| Same identity and same input while running | Refuse a second live stream. |
| Same identity and same input after completion | Return the recorded start, optional state snapshot, and terminal event. |
| Same identity with different input | Raise a run conflict. |

Reconnect does not replay text or tool deltas. Replaying deltas could display text twice or repeat a side effect. The host can publish a state snapshot for a finished run, but the gem does not reconstruct conversation history.

The same rule applies to a completed approval-resume run. Resend its exact
input, including `resume`, with the original run id to receive the recorded
outcome without applying the decision again. A new run id that tries to answer
an already answered interrupt is refused. Changing the input under an existing
run id is a conflict.

## Choose a Store

`MemoryStore` is suitable for tests and a single process. Its records disappear on restart and are not shared between workers. The Rails adapter's `ActiveRecordStore` persists records and redeems interrupts under a database lock.

The store boundary is `RubyLLM::AgUI::Store::Base`. Configure a compatible store globally or pass it to `Run.new`. For multi-process deployments, the database must enforce unique run identity and serialize interrupt redemption.

## Next Steps

* [Configuration]({% link _getting_started/configuration.md %}) - set the default store.
* [Rails Integration]({% link _advanced/rails-integration.md %}) - install the durable ActiveRecord store.
* [Protocol Coverage]({% link _reference/protocol-coverage.md %}) - inspect reconnect events.
