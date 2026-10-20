---
layout: default
title: Upgrading
nav_order: 2
description: Move a RubyLLM AG-UI application to the next release, one release at a time.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to move between versioned releases.
* Where to find changes that need code updates.

## Move from 0.2 to 0.3

Drain your old workers, change your Gemfile, and update the dependency:

```ruby
gem 'ruby_llm-ag_ui', '~> 0.3.0'
```

```sh
bundle update ruby_llm-ag_ui
```

Version 0.3 requires JSON 2.x. Rails 8.0 passes an option removed in JSON 3
when RubyLLM loads its chat class. If your Gemfile pins JSON 3, remove that pin
or select JSON 2.x before updating. This bound also applies to plain Ruby hosts.

`Run` now continues after a response write or flush fails. It saves the real
outcome instead of reporting the disconnected client as a failed run. Hosts
that previously relied on disconnects to stop work must explicitly request
cancellation on the authorized chat. `SSEWriter` still raises a `StreamError`
subclass when used directly. See
[Streaming Runs]({% link _core_features/streaming-runs.md %}).

Store writes now use an atomic revision check. Always retain the record returned
by `save`. Custom stores must implement this contract before upgrading. Existing
JSON payloads load with revision zero and the shipped table needs no migration.
Drain old workers first, since 0.2 writers do not enforce revision checks.
`PersistenceError` now propagates storage failures without guessing a terminal
outcome. Read [Worker Recovery]({% link _advanced/worker-recovery.md %}) for
explicit recovery and external-effect reconciliation.

Faraday request timeouts now use `transport_timeout` instead of the generic
`transport_error` code. Both remain failed outcomes. See
[Cancellation and Timeouts]({% link _core_features/cancellation.md %}).

## Older Releases

For earlier upgrade steps, read the
[0.2 upgrading guide](https://github.com/yorzi/ruby_llm-ag-ui/blob/v0.2.0/docs/_reference/upgrading.md).
