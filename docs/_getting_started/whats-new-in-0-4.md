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

Version 0.4 is in development. Read
[Compatibility]({% link _reference/compatibility.md %}) for recorded results
and limits; an intended matrix is not a completed verification.
