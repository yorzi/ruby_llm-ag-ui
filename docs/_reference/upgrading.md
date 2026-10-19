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

## Develop against 0.3

Version 0.3 is unreleased. Use the `main` checkout to test these changes.
The latest published release remains 0.2.

`Run` now continues after a response write or flush fails. It saves the real
outcome instead of reporting the disconnected client as a failed run. Hosts
that previously relied on disconnects to stop work must explicitly request
cancellation on the authorized chat. `SSEWriter` still raises a `StreamError`
subclass when used directly. See
[Streaming Runs]({% link _core_features/streaming-runs.md %}).

## Move from 0.1 to 0.2

Change your Gemfile and update the dependency:

```ruby
gem 'ruby_llm-ag_ui', '~> 0.2.0'
```

```sh
bundle update ruby_llm-ag_ui
```

The 0.2 release keeps the 0.1 run, store, and Rails APIs. It does not require
another migration or installer run.

Tool progress is off by default. Set `config.emit_tool_progress = true` only
when your client handles activity snapshots, and review its redaction policy.
See [Tool Progress]({% link _core_features/tool-progress.md %}).

## Completed Resume Retries in 0.2

An exact retry of a completed resume run now returns its recorded outcome.
Keep the original run id and full input, including `resume`. A new run id that
tries to answer an already answered interrupt is still refused, and changed
input under the original id is a conflict. No approval or tool is executed again.

## Older Development Checkouts

For the initial release's generator namespace correction, read the
[0.1 upgrading guide](https://github.com/yorzi/ruby_llm-ag-ui/blob/v0.1.0/docs/_reference/upgrading.md).
