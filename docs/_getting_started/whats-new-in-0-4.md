---
layout: default
title: "What's New in 0.4"
nav_order: -1
description: Review the public integration contract and verified compatibility boundaries.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* Which configuration changes need an application update.
* Where to find the proposed public API and compatibility evidence.

## Use Effective Configuration

```ruby
RubyLLM::AgUI.configure do |config|
  config.protocol_version = '1.0'
end
```

Other protocol versions raise `ConfigurationError`. The unused
`allow_client_history` setting is removed. Client history remains the host's
responsibility. See [Upgrading]({% link _reference/upgrading.md %}).

## Preserve Immutable Request and Store Values

Parsed input and JSON record values now copy and freeze their nested members.
Changing a caller's original state cannot change a stored snapshot or identity.
Use new inputs and record transitions instead of editing nested values. See
[Reconnects]({% link _core_features/reconnects.md %}).

The [Public API Contract]({% link _reference/public-api.md %}) identifies
application and custom-store APIs and separates orchestration internals.

## Associate Resumed Tool Results Once

Real RubyLLM approval resumes now emit the result of the original call without
repeating its start and arguments. The offline real-chat and opt-in provider
checks use the same harness. `Run#record` also exposes the recorded outcome
after a reconnect, matching the return value from `stream`. See
[Approval and Resume]({% link _core_features/approval-and-resume.md %}).

## Verify the Provider Separately

The opt-in harness checks OpenRouter text and a synthetic approval/resume
without external business effects. The same real RubyLLM chat setup has offline
HTTP tests. See [Provider Verification]({% link _advanced/provider-verification.md %})
for credential handling, request limits, and the scope of the results.

Read
[Compatibility]({% link _reference/compatibility.md %}) for recorded results
and limits; an intended matrix is not a completed verification.
