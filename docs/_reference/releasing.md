---
layout: default
title: Releasing
nav_order: 10
description: Verify an installed gem artifact and publish its matching version tag through RubyGems trusted publishing.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to check a release artifact outside the checkout.
* Which settings bind RubyGems to the release workflow.
* How a version tag publishes the gem and its documentation.

## Verify the Package

```bash
bundle exec rake
npm ci
bin/check-browser
bundle exec bundle-audit check --update
bundle exec rake build
bundle exec ruby scripts/check_package_host.rb --built
bundle exec ruby bin/verify-package --rails --audit
docs/bin/build.sh
python3 scripts/check_docs_links.py
```

The package check installs dependencies in a fresh temporary gem home and requires the installed artifact from outside the checkout. It verifies the core entrypoint, shipped templates and guides, and input parsing. With `--rails`, it invokes the documented generator and migrates its table up and down in SQLite. With `--audit`, it checks the actually activated core dependencies against the advisory database.

These checks make no live provider call. Keep provider and client interoperability evidence in [Compatibility]({% link _reference/compatibility.md %}).

Install the documentation bundle before building the site: run `bundle install`
from `docs/`. API HTML and Markdown use the RDoc version locked in that bundle,
so local and CI builds use the same navigation and parser.

## Review Release Scope

Use the repository's [roadmap](https://github.com/yorzi/ruby_llm-ag-ui/blob/main/ROADMAP.md)
for proposed iterations and the 1.0 release conditions. Guides describe available
behavior; the roadmap describes planned work. Check the release's conditions
before preparing its tag.

## Configure Trusted Publishing

Before the first tag, register a pending trusted publisher on RubyGems with gem name `ruby_llm-ag_ui`, GitHub owner `yorzi`, repository `ruby_llm-ag-ui`, workflow `release.yml`, and environment `release`. The workflow uses a short-lived GitHub OIDC identity instead of a stored RubyGems API key.

## Prepare the Release Commit

Match the version in `lib/ruby_llm/ag_ui/version.rb` and `docs/_config.yml`. Set `released: true`, add a dated CHANGELOG section, update [Release History]({% link _reference/release-history.md %}), and record upgrade steps in [Upgrading]({% link _reference/upgrading.md %}). For a minor release, add its What's New guide.

Push the completed commit to `main` and wait for CI to pass. Tag that exact commit:

```bash
git tag -a v{{ site.version }} -m "Release {{ site.version }}"
git push origin v{{ site.version }}
```

Replace the example tag with the version you are releasing. The `Release Gem` workflow rejects a tag that differs from the gem or docs version, or lacks a CHANGELOG section. It runs offline checks, the advisory audit, and isolated package verification before publishing.

## Confirm Publication

On success, the workflow creates a GitHub Release with the gem, checksum, and CHANGELOG notes. The Docs workflow runs after the release workflow succeeds. It publishes the tagged version at `/` and current `main` at `/next/`.

Check the version on RubyGems, the GitHub Release assets, and the documentation installation command. If a publish attempt fails, inspect its logs before retrying. A published RubyGems version cannot be overwritten.

Download the published gem from both RubyGems and the GitHub Release. Compare
their SHA-256 hashes with the release's `SHA256SUMS` and RubyGems metadata.
Verify that its packaged files match the tag. The publish job builds its own
artifact, so a verification job's earlier hash is not proof of the public bytes.

Place the downloaded gem under `pkg/` and repeat the installed-host check with
`--built`, followed by `bin/verify-package --rails --audit`. Do not rebuild the
gem between downloading and checking it. Confirm the rendered stable and
`/next/` guides, API links, and version menu after the Docs deployment succeeds.
