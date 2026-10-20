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

## Develop against 0.4

Version 0.4 is unreleased. Use the main checkout for these changes.
The latest published release remains 0.3.

Remove assignments to `config.allow_client_history`. The unused setting is
removed, including its diagnostic key. The gem never imports client messages
into the host chat; reconcile history in your host application.

`config.protocol_version` remains `"1.0"`. Assigning any other value now raises
`ConfigurationError` instead of accepting a setting the emitted events ignore.

## Older Releases

Read the [0.3 upgrading guide](https://github.com/yorzi/ruby_llm-ag-ui/blob/v0.3.0/docs/_reference/upgrading.md)
for JSON 2.x, worker draining, and the custom-store revision contract.
