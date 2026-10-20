---
layout: default
title: API Reference
nav_order: 1
guide: false
description: Browse RDoc pages generated from classes and methods in the gem source.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

Read the [Public API Contract]({% link _reference/public-api.md %}) before
depending on a class. The [API reference]({{ '/api/' | relative_url }}) opens on the `RubyLLM` module. The generated pages follow the RDoc comments in `lib/`.

| Build with | Reference |
| --- | --- |
| Configure defaults | [`RubyLLM::AgUI::Configuration`]({{ '/api/RubyLLM/AgUI/Configuration.html' | relative_url }}) |
| Parse a request | [`RubyLLM::AgUI::Input`]({{ '/api/RubyLLM/AgUI/Input.html' | relative_url }}) |
| Stream a chat turn | [`RubyLLM::AgUI::Run`]({{ '/api/RubyLLM/AgUI/Run.html' | relative_url }}) |
| Inspect event coverage | [`RubyLLM::AgUI::Coverage`]({{ '/api/RubyLLM/AgUI/Coverage.html' | relative_url }}) |
| Store run state | [`RubyLLM::AgUI::Store::MemoryStore`]({{ '/api/RubyLLM/AgUI/Store/MemoryStore.html' | relative_url }}) |

For Markdown, start with the [class index]({{ '/api/index.md' | relative_url }}). Every HTML class page has a matching `.md` page.

The reference is generated from source comments with RDoc. Build it locally with `docs/bin/build-api.sh tmp/api`.
