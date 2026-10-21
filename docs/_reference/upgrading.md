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

## Move from 0.4 to 1.0.0.rc.1

Update your Gemfile and dependency:

```ruby
gem 'ruby_llm-ag_ui', '1.0.0.rc.1'
```

```sh
bundle update ruby_llm-ag_ui
```

The release candidate keeps the 0.4 public API, configuration, and store
contract. It needs no SQL migration, and the generated migration and
initializer are unchanged. Records written by 0.4 stay readable: an exact retry
reconnects to a 0.4 run, and a 0.4 interrupt can be resumed after the upgrade.

Clients now receive tool argument deltas that join to valid JSON for every
streamed call. If your client worked around the old `{}` prefix or Ruby
`Hash#to_s` arguments, remove that workaround.

Requiring the gem no longer loads `ActiveRecord::Base` during a Rails boot.
Code that relied on the gem to load Active Record must load it itself.

## Move from 0.3 to 0.4

Update your Gemfile and dependency:

```ruby
gem 'ruby_llm-ag_ui', '~> 0.4.0'
```

```sh
bundle update ruby_llm-ag_ui
```

This release keeps JSON 2.x and the 0.3 store revision contract. It needs no
additional SQL migration. Drain old workers before replacing their code.

Remove assignments to `config.allow_client_history`. The unused setting is
removed, including its diagnostic key. The gem never imports client messages
into the host chat; reconcile history in your host application.

`config.protocol_version` remains `"1.0"`. Assigning any other value now raises
`ConfigurationError` instead of accepting a setting the emitted events ignore.

Nested request and JSON record values are now read-only. In-place edits raise
`FrozenError`. Build a new input, or use record transitions and `store.save`,
instead of mutating ids, snapshots, failure hashes, or interrupt values.
Caller-owned JSON objects remain mutable and do not alias the stored record.

## Older Releases

Read the [0.3 upgrading guide](https://github.com/yorzi/ruby_llm-ag-ui/blob/v0.3.0/docs/_reference/upgrading.md)
for JSON 2.x, worker draining, and the custom-store revision contract.
