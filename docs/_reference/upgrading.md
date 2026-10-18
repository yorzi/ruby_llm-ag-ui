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

## One Release at a Time

Version `0.1.0` is the first release. There is no earlier published version to upgrade from. Start with [Getting Started]({% link _getting_started/getting-started.md %}). For future releases, upgrade one release at a time.

## Install Version 0.1

```ruby
gem 'ruby_llm-ag_ui', '~> 0.1.0'
```

If you used an untagged development checkout, review [Configuration]({% link _getting_started/configuration.md %}) and [Rails Integration]({% link _advanced/rails-integration.md %}) before changing the dependency. No compatibility with earlier untagged checkouts is promised.

## Use the Full Generator Command

Untagged development checkouts registered the shorter `ruby_llm:ag_ui` namespace. Version 0.1 registers the documented installation command:

```bash
# Before, on an untagged checkout
bin/rails generate ruby_llm:ag_ui

# Version 0.1
bin/rails generate ruby_llm:ag_ui:install
```

Existing generated tables and initializers do not need to be regenerated for this command-name correction.

## Completed Resume Retries in 0.2

An exact retry of a completed resume run now returns its recorded outcome.
Keep the original run id and full input, including `resume`. A new run id that
tries to answer an already answered interrupt is still refused, and changed
input under the original id is a conflict. No approval or tool is executed again.
