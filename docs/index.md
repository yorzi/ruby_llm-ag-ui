---
layout: home
title: "RubyLLM AG-UI"
description: "Run RubyLLM chats as AG-UI 1.0 streams with validated input, approval pauses, cancellation, and optional Rails integration."
permalink: /
hero:
  name: "RubyLLM AG-UI"
  text: "Run RubyLLM chats as AG-UI agent runs"
  tagline: "An unofficial Ruby gem for connecting RubyLLM applications to AG-UI clients."
  actions:
    - theme: brand
      text: Get started
      link: /getting-started/
    - theme: alt
      text: View on GitHub
      link: https://github.com/yorzi/ruby_llm-ag-ui
features:
  - title: Ordered event streams
    details: Map one RubyLLM chat turn to one AG-UI run with a single recorded outcome.
    link: /streaming-runs/
    link_text: Stream a run
  - title: Safe input and approval
    details: Validate RunAgentInput and resume approved tool calls on a new run.
    link: /input-validation/
    link_text: Validate input
  - title: Optional Rails adapter
    details: Add a controller concern and a durable ActiveRecord store to a Rails app.
    link: /rails-integration/
    link_text: Use with Rails
---

## Install

```sh
{% if site.docs_unreleased %}bundle add ruby_llm-ag_ui --git https://github.com/yorzi/ruby_llm-ag-ui --branch main{% else %}bundle add ruby_llm-ag_ui --version {{ site.version }}{% endif %}
```

## Parse a request

```ruby
require 'ruby_llm/ag_ui'

input = RubyLLM::AgUI::Input.parse({
  'threadId' => 'thread-1',
  'runId' => 'run-1',
  'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Hello' }]
})

puts "#{input.thread_id}/#{input.run_id}"
# => thread-1/run-1
```

[Get started]({% link _getting_started/getting-started.md %}) or read [how a run works]({% link _getting_started/overview.md %}).
