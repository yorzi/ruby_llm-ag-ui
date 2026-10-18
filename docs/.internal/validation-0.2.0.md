# 0.2.0 local candidate validation

2026-10-19, macOS arm64. Development starts at `454c587`; implementation units
include `45db83e`, `4b7944b`, `c5a2eec`, `3a1befd`, `d40da8d`, and `7da0be7`.
The candidate version is 0.2.0 with documentation `released: false`. No 0.2 tag,
push, gem upload, hosted deployment, or remote CI result is part of this work.

## Delivered

- One maintained offline client host serves plain Ruby and Rails endpoints.
  Chats persist per fixture actor/thread in one process; run records use a
  disposable SQLite database and the installed generator's migration.
- Opt-in `emit_tool_progress` publishes replacing `TOOL_PROGRESS` activity
  snapshots. Per-call identity is stable; values pass through redaction.
  Concurrent callbacks and finalization share a lock, and late callbacks stop.
- An exact completed resume request reconnects without redeeming its decision
  again. Changed input conflicts, and a new run cannot reuse an answered approval.
- Agent commands run core/lint/example, installed-host, browser, and rendered
  documentation checks. Browser failures retain the actual page and trace.
  CI and release verification include these checks; CI has not been run remotely.

## Results

| Check | Observed result |
| --- | --- |
| RSpec, Ruby 3.3.5 / RubyLLM 2.1.1 / Rails 8.1.4 | 247 examples, zero failures, one opt-in provider example skipped |
| RuboCop | 82 Ruby files, no offenses |
| Real browser | 12 scenarios pass with `@ag-ui/client` 1.0.3, Playwright 1.64.1, Chrome 155.0.8059.82 |
| Client event schema | 154 captured events across the 12 scenarios validate against the pinned schema |
| Screenshots | Desktop progress before completion and 390px denial layout inspected; no horizontal overflow in the asserted mobile cases |
| Installed artifact | Both endpoints pass approval, progress, and completed-resume reconnect; entrypoint resolves to the installed gem, outside the checkout |
| Rails example models | Generated RubyLLM tables, ordered example migrations, and actor-scoped persisted chats pass |
| Clean GEM_HOME | Core loading, input parser, shipped templates/guides, and Rails generator migration up/down pass |
| Advisory checks | Root lock and activated clean core dependencies have no findings against 1,266 advisories at `fa2295251efb3b0d1a300e5ce8ad700ff1f1b485` |
| Docs source | 20 guides, zero errors; two expected warnings for unreleased 0.2.0 versus latest tag v0.1.0 |
| Versioned build | Stable v0.1.0 and working-tree 0.2.0 build; development retains its own version |
| Rendered links | 8,839 links across 135 HTML pages, zero errors |

The installed-host and clean-install checks use copies of the same frozen
`pkg/ruby_llm-ag_ui-0.2.0.gem`:

```text
SHA256=e4d49181e437f234d37d442b82ff6e4786aacd1c9c7d3cec4cb2cef19003e3ee
```

This identifies the tested artifact; it is not a reproducible-build claim.
The installed-host probe reuses available development dependencies. The clean
GEM_HOME check separately resolves runtime dependencies, verifies their actual
activated versions, and installs Rails for its generator smoke check.
Development assets, databases, screenshots, and internal records are absent
from the gem.

## Regression probes and artifacts

Removing the live harness scope fails before any provider call. Temporarily
removing progress redaction, stable activity identity, closed-run suppression,
or the finalization lock makes the focused tests fail. Sources are restored
and the final suite is green.

An intentionally wrong browser assertion produces a nonblank screenshot of the
interrupted page and a Playwright trace. The assertion is restored. Control
reset and accessible select labels are also covered by the final green suite.

Local artifacts, not committed:

- Final browser run: `tmp/browser/2026-10-18T23-40-39-578Z-97912/`.
- Failure-artifact probe: `tmp/browser/2026-10-18T23-29-24-845Z-93662/`.
- Package-host and other focused logs: `tmp/validation/`.

## Reproduce and limits

```sh
bundle install
npm ci
bin/check --package --browser
bundle exec rake build
bundle exec ruby scripts/check_package_host.rb --built
bundle exec bundle-audit check --update
bundle exec ruby bin/verify-package --rails --audit
docs/bin/build.sh
python3 scripts/check_docs_links.py
```

These are synthetic, local results. No live provider, CopilotKit, PostgreSQL,
MySQL, or full Ruby/Rails version-matrix claim follows from them. WebMock and
browser route guards limit test HTTP requests; they are not a system firewall.
The fixture actor header and disabled CSRF checks are not production security.

Temporary hosts and databases are removed on exit. Playwright closes browser
sessions and the runner stops its owned server. A final process audit finds no
demo server or test-browser profiles, and port 3199 has no listener.
