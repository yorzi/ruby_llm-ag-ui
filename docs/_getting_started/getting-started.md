---
layout: default
title: Getting Started
nav_order: 1
description: Install ruby_llm-ag_ui and validate an AG-UI request before connecting a chat.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to install the release or the current development branch.
* How to parse a `RunAgentInput` into validated Ruby values.
* How to run the included offline end-to-end example.

## Installation

```sh
{% if site.docs_unreleased %}bundle add ruby_llm-ag_ui --git https://github.com/yorzi/ruby_llm-ag-ui --branch main{% else %}bundle add ruby_llm-ag_ui --version {{ site.version }}{% endif %}
```

The gem requires Ruby 3.2 or newer, RubyLLM 2.1 or newer, and `ag-ui-protocol` 0.2.x. The Rails adapter is optional. Provider credentials belong to your RubyLLM application; the parser example below needs none.

The runtime dependencies select patched `cgi`, `resolv`, `uri`, and `zlib` gems. An older Ruby installation's default library versions do not override those dependency requirements.

## Parse a Request

Before you start a chat, validate the request body. The parser bounds the input, checks required fields, and returns an immutable value.

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

The host still chooses the chat, model, tools, and authenticated scope. `Input` treats client fields as data and does not grant access. To see a complete run with an approval pause and resume, run `bundle exec rake example` from the repository; it uses a scripted chat and needs no provider key.

## Next Steps

* [How RubyLLM AG-UI Works]({% link _getting_started/overview.md %}) - the parts of one run.
* [Configuration]({% link _getting_started/configuration.md %}) - defaults and run stores.
* [Validating Input]({% link _core_features/input-validation.md %}) - request limits and strict parsing.
