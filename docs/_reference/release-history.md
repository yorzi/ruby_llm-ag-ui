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

{% if site.docs_unreleased %}This build follows `main`. The latest stable release is `{{ site.version }}`.
{% else %}This documentation describes version `{{ site.version }}`. Use its tag and release notes to identify the exact source.
{% endif %}

| Release | Date | Highlights |
| --- | --- | --- |
| [0.1.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.1.0) | 2026-10-18 | [First release]({% link _reference/whats-new-in-0-1.md %}): AG-UI event mapping, approval and resume, cancellation, reconnect, and the optional Rails adapter |

To move an application from one release to the next, follow [Upgrading]({% link _reference/upgrading.md %}).
