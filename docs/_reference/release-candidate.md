---
layout: default
title: Candidate Acceptance
nav_order: 8
description: Install the local 1.0 candidate and check your application before approving the stable release.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to install the candidate from its gem file.
* Which application behaviors to check before 1.0.
* What remains required before publishing the stable version.

## Build the Local Artifact

```sh
bundle install
bundle exec rake build
shasum -a 256 pkg/ruby_llm-ag_ui-{{ site.version }}.gem
```

The candidate is not tagged or published on RubyGems. Keep the gem file and
its SHA-256 with your test results. Rebuilding can change the archive hash;
test and share the same file throughout acceptance.

## Install in Your Application

Set the exact version in your application's Gemfile. Remove any `path:` or
`git:` option for this gem so Bundler uses the installed artifact:

```ruby
gem 'ruby_llm-ag_ui', '{{ site.version }}'
```

From that application, copy and install the candidate. Replace the example
source path with the actual gem file:

```sh
mkdir -p vendor/cache
cp /absolute/path/to/pkg/ruby_llm-ag_ui-{{ site.version }}.gem vendor/cache/
gem install vendor/cache/ruby_llm-ag_ui-{{ site.version }}.gem --no-document
bundle update ruby_llm-ag_ui --local
bundle exec ruby -rruby_llm/ag_ui -e 'puts RubyLLM::AgUI::VERSION; puts Gem.loaded_specs.fetch("ruby_llm-ag_ui").full_gem_path'
```

`gem install` can download ordinary runtime dependencies. The application must
already have its other dependencies installed for Bundler's `--local` update.
The last command must show the candidate version and an installed gem directory,
not this repository's checkout. Commit the application's intended lockfile change
only after reviewing its dependency diff.

For a new Rails application, follow
[Rails Integration]({% link _advanced/rails-integration.md %}) for generator and
RubyLLM model setup. For a 0.4 application, no new SQL migration is required;
keep the existing initializer and table. Drain old workers before replacing
their code. See [Upgrading]({% link _reference/upgrading.md %}).

## Check Your Real Application

Use a disposable database and a synthetic tool with an observable counter.
Start with ordinary text, then run a tool and an approval pause. Check both
approval and denial, including a retry of the exact completed request. Your
application still owns authorization, chat persistence, and provider setup.

| Check | Expected result |
| --- | --- |
| Text and consecutive tool rounds | Text is not duplicated; each call opens once and has parseable JSON arguments and an associated result |
| Approval, denial, and retry | No effect before approval, one after approval, zero after denial, no repeated effect on reconnect |
| Actor isolation | Another actor cannot access the chat, reconnect to its outcome, or answer its interrupt |
| Cancellation and failure | The host cancels the exact run; failure output and logs withhold private details |
| Disconnect and worker restart | A completed reconnect does not rerun the provider or tool; unknown worker effects require explicit reconciliation |
| Upgrade from 0.4 | Existing completed records reconnect and pending interrupts resume after draining old workers |
| HTTP refusals | Invalid input returns 400 or 413; conflicting identity returns 409; an effective SSE quality of zero returns 406 before chat resolution |

Record Ruby, Rails, RubyLLM, client, provider/model, artifact hash, and the
observed results. Keep credentials and real customer payloads out of reports.
Automated browser fixtures do not replace this application-specific check.

## Reproduce the Automated Upgrade Check

```sh
gem fetch ruby_llm-ag_ui --version 0.4.0
bundle exec ruby bin/verify-upgrade ruby_llm-ag_ui-0.4.0.gem
```

The command runs from the gem repository after building the candidate. It
installs both artifacts in a temporary gem home and activates them in separate
processes against one temporary SQLite database. It checks generated files,
persisted 0.4 outcomes, approval, denial, reconnect, and scope isolation. It uses
available development dependencies and a scripted chat, with no provider call.
Use `bin/verify-package --rails --audit` separately for fresh dependency resolution.

## Approve the Stable Release

Keep RC publication disabled. After the maintainer accepts the real installation,
fix any reported defect and repeat affected checks. Then prepare version 1.0.0,
date its changelog, update the stable installation instructions, and rerun the
[release checks]({% link _reference/releasing.md %}) before tagging and publishing.
No test count or coverage percentage establishes that every host or provider
works. [Compatibility]({% link _reference/compatibility.md %}) records the limits.
