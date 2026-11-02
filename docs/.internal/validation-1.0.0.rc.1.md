# Unpublished 1.0 candidate acceptance

Local review on 2026-10-26, macOS arm64, Ruby 3.3.5. Candidate source:
`b9f58cb`. The candidate remains `1.0.0.rc.1`, with `released: false`.
No RC tag, GitHub Release, or RubyGems publication is authorized by this review.
The next intended publication is 1.0.0 after maintainer installation acceptance.

## Findings and verified changes

- The existing local RC work already fixes multi-round streamed tool calls,
  provider argument shapes, early Active Record loading, malformed text,
  callable policy objects, and retained response streams.
- `9ef01d0`: an SSE header with effective quality zero previously started a
  run. Focused tests fail before the fix; Rails now returns 406 before chat
  resolution or reservation. Specific ranges override wildcards. The final
  review also covers empty media parameters, with its own failing regression.
- `84c10e7`: a real Rails host without Active Record reproduced a missing
  constant while handling a stream refusal. The new subprocess fixture verifies
  409 and propagation of unrelated host errors. A separate test retains the
  sanitized Active Record 404 response.
- `c94ae8d`: npm reported four high findings from one transitive Zod advisory.
  The pinned client/core schema code imports `zod/v4`. An explicit override to
  Zod 4.6.6 removes the findings and retains all browser workflows.
- The local Rails development lock selected vulnerable crass 1.0.7. Updating
  it to 1.0.8 clears the Ruby audit. The root lockfile is ignored; fresh CI
  resolves dependencies independently. No host application lockfile is altered.
- `b9f58cb`: add the repeatable two-artifact upgrade command and CI audit
  steps; correct README installation, changelog, release history, and roadmap
  to state that the RC is unpublished. Add the maintainer acceptance guide.

## Local results

| Check | Result |
| --- | --- |
| Core and lint | 320 examples, zero failures, two opt-in skips; 100 files without lint offenses |
| Minimum dependency | Separate full 320-example suite passes on RubyLLM 2.1.0; the current selected version is 2.1.1 |
| Coverage | 1,335 of 1,368 measured lines, 97.58 percent; no claim of complete behavior coverage |
| Real client | 18 workflows, 242 schema-valid consumed events; client 1.0.3, Playwright 1.64.1, overridden Zod 4.6.6 |
| Visual inspection | Desktop approval progress and 390px mobile Rails denial screenshots inspected |
| Live provider | OpenRouter / openai/gpt-4.1-mini; two live cases and one offline harness case pass, no failures |
| Ruby audit | 1,269 advisories at 03da937a9e171e3fedebde6620e203559b7a60c0, no findings after crass update |
| npm audit | Zero findings after the Zod override |
| Installed host | Both endpoints, approval/progress/reconnect, generated RubyLLM models and scoped persistence pass |
| Fresh resolution | Core loads outside the checkout; activated-core audit, Rails generator and migration up/down pass |
| Bundler application | An isolated 0.4 Gemfile/lock upgrades with the cached RC artifact and --local; runtime loads the installed candidate |
| Upgrade | Unchanged generated files; persisted 0.4 completion reconnect, approval once, denial with zero effect, exact retries, scope isolation |
| Documentation | 28 guides, zero errors and two expected unpublished-version warnings; 8,920 links in 142 built pages, zero errors |

Browser evidence:
`tmp/browser/2026-10-26T06-10-46-107Z-65754/`.
Fresh-install evidence:
`/var/folders/lg/2wcb539s3x79yz10zq8ltv1m0000gn/T/ag-ui-package-20261026-67245-hfzjra`.
Logs remain under ignored `tmp/validation/rc-20261026/`. The first shell attempt
used system Ruby 2.6 and failed before testing; all recorded checks above use
the existing Ruby 3.3.5 runtime. The Bundler host probe needed network access
to cache a Ruby default gem before its local upgrade could complete.

## Fixed local artifact

```text
pkg/ruby_llm-ag_ui-1.0.0.rc.1.gem
SHA256=639ef2938232be5bfe13bda5089bdbb152075b1ba38af90d01b2ee718e676b46
```

All 68 packaged files match `b9f58cb` byte for byte. The manifest matches the
gemspec; internal evidence, tests, node_modules, and generated sites are absent.
Installed-host, upgrade, and fresh-install checks use that same artifact without
rebuilding. Its checksum is in `pkg/SHA256SUMS-1.0.0.rc.1`.
The baseline is the actual 0.4.0 download with SHA-256
`e98b51b3c3465af99ed894cb94689a16cbdb31107a92d7203250d454cdb4ddb8`.
The isolated core activates JSON 2.7.1, RubyLLM 2.1.1, and protocol SDK 0.2.0.
Subsequent internal evidence commits do not alter any packaged file.

Remote CI is separate evidence: inspect the Actions runs for the final pushed
commit. The source workflow now includes upgrade verification and Ruby/npm
audits. No publication workflow should run because no tag is created.

## Remaining acceptance and cleanup

The maintainer still needs to install this fixed artifact in a real application
and verify its authentication, chat persistence, actual client/provider path,
upgrade, and recovery wiring using the Candidate Acceptance guide. That is the
remaining release decision. Resolve reported defects and repeat affected checks
before preparing 1.0.0.

Live denial, cancellation timing, provider/Rails browser sessions, other models
or providers, and non-SQLite stores remain unverified. Existing host lockfiles
need independent advisory checks. The upgraded SQLite fixture uses a scripted
chat and available development dependencies; it is not live-provider evidence.

Browser runners close their browsers and loopback servers on exit. Temporary
upgrade and Bundler hosts are removed automatically; no preview service is
needed after acceptance. Generated logs, database evidence, and the fixed
candidate stay in ignored directories.

## Addendum: 2026-11-02 review

Candidate source `92a8116` (code) and `3e00433` (CI and evidence). The review of
every change since 0.4.0 found one defect: a streamed fragment with a new id
under a reused stream index continued the call at that index, unlike RubyLLM's
accumulator. The new intercepted-HTTP spec fails before the fix.

| Check | Result |
| --- | --- |
| Core and lint, Ruby 3.3.5 | 321 examples, zero failures, two opt-in skips; 100 files without offenses |
| Ruby 4.0.9 | 321 examples pass with RubyLLM 2.1.1 / Rails 8.1.4, and with RubyLLM 2.1.0 / Rails 8.0.5.1 |
| Malformed input | Refused as `MalformedInputError` on JSON 2.7.1, 2.9.1, and 2.21.2 |
| Real client | 18 workflows, 242 schema-valid consumed events; screenshots inspected |
| Installed host | Both endpoints, generator/migration, approval, progress, reconnect, generated RubyLLM models |
| Upgrade | From the 0.4.0 download (`e98b51b3...`): unchanged generator, reconnect, approval once, denial, scope isolation |
| Documentation | Site builds; v0.4.0 at / and the working tree at /next/ |

Rebuilt artifact, superseding the 2026-10-26 hash above:

```text
pkg/ruby_llm-ag_ui-1.0.0.rc.1.gem
SHA256=76b52b249e9cc922ba91c186f754276347dcd972886e3e8f9873d6e54fad4b00
```

The superseded artifact is kept under ignored `tmp/superseded-rc1-20261026/`.
Logs are under ignored `tmp/validation/review-20261102/`; browser evidence is in
`tmp/browser/2026-11-02T12-50-15-952Z-33029/`. Remote CI with Ruby 4.0 has not
run yet; nothing is pushed, tagged, or published. Maintainer acceptance remains
the release decision.
