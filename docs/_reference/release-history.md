---
layout: default
title: Release History
nav_order: 9
guide: false
description: Review RubyLLM AG-UI releases, newest first, with highlights and upgrade guidance.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

{% if site.docs_unreleased %}This build follows `main` for version `{{ site.version }}` development. Select Stable in the version menu for the published release.
{% else %}This documentation describes version `{{ site.version }}`. Use its tag and release notes to identify the exact source.
{% endif %}

| Release | Date | Highlights |
| --- | --- | --- |
| [1.0.0.rc.1](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v1.0.0.rc.1) | 2026-10-21 | [Release candidate]({% link _getting_started/whats-new-in-1-0.md %}): streamed tool calls fixed across provider protocols, deferred Active Record loading, and a rehearsed upgrade from 0.4 |
| [0.4.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.4.0) | 2026-10-21 | [API and compatibility]({% link _reference/whats-new-in-0-4.md %}): effective configuration, immutable records, and real-chat approval verification |
| [0.3.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.3.0) | 2026-10-20 | [Lifecycle and worker recovery]({% link _reference/whats-new-in-0-3.md %}): disconnect handling, scoped cancellation, and conditional durable writes |
| [0.2.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.2.0) | 2026-10-19 | [Client workflows and tool progress]({% link _reference/whats-new-in-0-2.md %}): opt-in redacted progress, a real-client demo, and completed resume reconnect |
| [0.1.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.1.0) | 2026-10-18 | [First release]({% link _reference/whats-new-in-0-1.md %}): AG-UI event mapping, approval and resume, cancellation, reconnect, and the optional Rails adapter |

To move an application from one release to the next, follow [Upgrading]({% link _reference/upgrading.md %}).
