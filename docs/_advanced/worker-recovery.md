---
layout: default
title: Worker Recovery
nav_order: 4
description: Close a run after confirmed worker loss without repeating unknown tool effects.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to close a run whose worker has stopped.
* How record revisions prevent stale writes.
* Why recovery cannot prove or undo tool effects.

## Recover a Stopped Worker

First confirm through your process manager that the producer has stopped.
Then load its record using an authorized scope and exact identity:

```ruby
record = store.find(scope: authenticated_scope, thread_id: thread_id, run_id: run_id)
raise 'Run not found' unless record

# The host has confirmed that the producer and its tool threads have stopped.
recovered = store.recover(record)
recovered.status # => :failed
recovered.failure.fetch('code') # => 'worker_lost'
```

Use `ActiveRecordStore` when the record must survive a process exit. Recovery
changes a reserved or started record to failed. It retains the identity,
snapshot, and input digest. The original request can reconnect to a sanitized
`RUN_ERROR` with code `worker_lost`; it cannot execute the run again.

Recovery does not stop a worker. A timeout, disconnected browser, or old
`updated_at` value does not prove the worker is dead. Confirm that all producer
and tool activity has stopped before calling this method. The gem does not
provide leases, worker discovery, or automatic recovery.

## Keep the Latest Record

Each successful store write increments `RunRecord#revision`. Keep the record
returned by `save` if you write it again:

```ruby
record = store.save(record.start(now: Time.now))
record = store.save(record.finish(:succeeded, now: Time.now))
```

`save` and `recover` raise `StaleRecordError` when the stored revision changed
since you read it. This error is a `RunConflictError`. Reload and inspect the
current outcome before making another decision. A terminal outcome cannot be
replaced by recovery. The revision is separate from event sequence numbers.

The memory store checks revisions under its mutex. The ActiveRecord store uses
a conditional database update against the observed payload. Competing approval
redemptions reload and revalidate after a conflict; a repeated decision is a
replay, and a disagreeing decision is refused.

## Handle an Uncertain Database Write

`Run#stream` raises `PersistenceError` if storage fails without a reliable
acknowledgement. It does not attempt another terminal write or send a guessed
`RUN_ERROR`. The first write may already have committed. When storage becomes
available, reload the exact identity. Reconnect if it ended; confirm the worker
has stopped before recovering a non-terminal record.

A stale or failed producer disables its mapper callbacks before returning, so
reusing its chat cannot append events to that old stream.

## Reconcile External Effects

A tool may complete its external change before the worker dies. A recovered
record says that execution ended without a recorded outcome; it does not say
that the tool failed or that no effect occurred. Inspect the external system
and use host-owned idempotency keys before starting another run. Never delete
the reservation to retry an uncertain effect. The gem does not promise
exactly-once external effects across crashes.

The host also serializes different run ids that share one mutable chat. Run
identity and approval redemption do not lock an entire conversation.

## Upgrade the Store Contract

The revision lives in the JSON payload, so the shipped table needs no new
migration. Records written before 0.3 load with revision zero. Drain old workers
before upgrading: a 0.2 writer does not honor the new conditional-write contract.
Custom stores must implement atomic revision checks, return the incremented
record from `save`, and provide the same recovery semantics as `Store::Base`.

## Next Steps

* [Reconnects and Run Identity]({% link _core_features/reconnects.md %}) - report a recorded outcome.
* [Security and Deployment]({% link _advanced/security-and-deployment.md %}) - keep authorization in the host.
