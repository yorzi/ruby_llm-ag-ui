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

This repository has no release tags yet, so there is no earlier versioned release to upgrade from. Once releases are tagged, each release will document its required code changes here. If an application skips several releases, upgrade one release at a time and resolve deprecation warnings before continuing.

## Changes in the Next Release

The current development version is `{{ site.version }}`. No breaking-change steps have been recorded for a published release. Each future entry will explain what changed, why, and the code before and after.
