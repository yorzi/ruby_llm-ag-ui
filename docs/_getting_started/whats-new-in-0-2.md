---
layout: default
title: "What's New in 0.2"
nav_order: 0
description: Verify real AG-UI client workflows and opt in to redacted tool progress.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to publish tool progress without exposing private messages.
* How to run the maintained browser client example.
* Which client checks run offline and which provider checks remain separate.

## Publish Tool Progress

Enable activity snapshots when your client supports them:

```ruby
RubyLLM::AgUI.configure do |config|
  config.emit_tool_progress = true
end
```

Progress is off by default. Each tool call has a stable activity id and later
snapshots replace earlier values. Values pass through the host redaction policy;
late callbacks cannot write after the run closes. See
[Tool Progress]({% link _core_features/tool-progress.md %}).

## Run the Official Client Locally

```sh
bundle install
npm ci
bin/check-browser
```

The maintained example connects a pinned official `@ag-ui/client` to plain Ruby
and Rails endpoints. It covers text, a second turn, approval/denial, progress,
completed-run reconnect, sanitized failure, and cancellation outcomes. The Rails
endpoint uses a generated migration and temporary SQLite database. See
[Client Example]({% link _advanced/client-example.md %}).

Browser screenshots, event traces, and schema validation are local fixture
evidence. They do not establish live provider behavior, all-client compatibility,
or remote CI success. The opt-in live spec now shares an actor-scoped setup
with an offline harness check. See
[Compatibility]({% link _reference/compatibility.md %}) and
[Upgrading]({% link _reference/upgrading.md %}) before updating your application.
