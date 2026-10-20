# 0.3.0 validation

The candidate sections below record local work before publication. See
Publication follow-up for the separately verified 2026-10-20 release.

2026-10-19, macOS arm64. Baseline: `7bb799d` after the 0.2.0 release.
Implementation commits: `e27a0d1`, `a01948f`, `820f732`, `546f06a`.
Version 0.3.0 is unreleased. No 0.3 push, remote CI result, release tag, upload,
or hosted deployment is claimed by this record.

## Delivered behavior

- Transport failure detaches the writer while the live producer continues.
  First write, text, progress, flush, closing events, and terminal writes are
  covered. Real Rails and Puma disconnect exceptions are normalized.
- Store revisions and conditional payload updates reject stale writes. Custom
  stores must adopt this contract, and hosts must drain 0.2 writers first.
- Explicit recovery closes a confirmed stopped worker's run as `worker_lost`,
  preserving identity and unknown-effect semantics. It never reruns a tool.
- Reservation, approval redemption, and terminal writes distinguish uncertain
  acknowledgements from run outcomes. A committed write is not replaced by a
  speculative failure, and failed producers disable their old callbacks.
- The demo separately exercises exact-run, actor-scoped host cancellation and
  HTTP abort. Wrong actors and run ids are refused; inactive cancellation and
  live retries get conflicts. HTTP abort does not cancel the producer.
- Real RubyLLM cancellation checkpoints and HTTP timeout classification run
  with intercepted HTTP and synthetic configuration, without a live provider.

## Local results

| Check | Result |
| --- | --- |
| Ruby 3.3.5 / RubyLLM 2.1.1 / Rails 8.1.4 | 284 examples, zero failures, one opt-in live-provider skip |
| RuboCop | 92 Ruby files, no offenses |
| Browser | 18 workflows pass with ag-ui/client 1.0.3, Playwright 1.64.1, Chrome 155.0.8059.82, Puma 8.0.2, Node 24.14.0 |
| Browser event schema | 242 consumed events validate against the pinned schema |
| Visual inspection | Desktop disconnection and 390px cancellation screenshots inspected; mobile overflow assertion passes |
| Independent SQLite workers | Seven scenarios use separate Ruby processes and database connections |
| Installed artifact | Both endpoints, approval/progress/reconnect, generated migrations and RubyLLM models, and actor-scoped persisted chats pass |
| Source docs | 23 guides, no errors; two expected unreleased-version warnings against v0.2.0 |
| Rendered docs | Stable v0.2.0 plus Next 0.3.0; 9,603 links in 144 pages, zero errors |
| Advisory database | Root lock has no findings against 1,266 advisories at fa2295251efb3b0d1a300e5ce8ad700ff1f1b485 |

The final artifact has 62 files. Development dependencies, screenshots,
databases, generated HTML, and internal validation notes are excluded.

## Fault and regression evidence

Independent-process barriers hold both writers after they read the old payload
and before either SQL update executes. Removing the SQL compare condition
produces two successful writers. Removing revision validation accepts stale
records. Both mutations fail their tests; original sources are restored and
the full suite passes.

The worker-loss scenario kills a real child process with SIGKILL after one
synthetic tool effect. A new process recovers and reconnects without completing
another tool effect. Separate tests refuse stale recovery and protect a
competing terminal outcome. This is not exactly-once external execution proof.

Browser regressions reproduce Puma's non-IOError disconnect and the plain Ruby
host's late live-retry refusal. After fixes, both backends return 409 for live
retries, preserve completed reconnect identity, and keep tool effects at one
when the browser aborts. Failure traces and phase screenshots remain under
ignored `tmp/browser/`; no generated test evidence is committed.

## Reproduce and limits

```sh
bin/check --package --browser
bundle exec rake build
bundle exec ruby scripts/check_package_host.rb --built
bundle exec bundle-audit check --update
bundle exec ruby bin/verify-package --rails --audit
docs/bin/build.sh
python3 scripts/check_docs_links.py
```

Use the Worker Recovery and Cancellation guides before adapting these fixtures.
Recovery requires confirmation that the producer and tool activity stopped;
an old timestamp is not proof. Cancellation is cooperative and does not undo
an external effect. The demo registry is single-process fixture infrastructure,
not a cross-worker cancellation service or production authentication layer.

Remote Ruby/Rails matrices, live providers, PostgreSQL/MySQL, and fresh public
0.3.0 downloads remain unverified. Historical 0.2 CI is recorded separately in
Compatibility and does not establish a 0.3 result.

## Final artifact and cleanup

The installed-host probe and fresh GEM_HOME verification use copies of the
same final `pkg/ruby_llm-ag_ui-0.3.0.gem`:

```text
SHA256=977b0644d0153c1b37035b4df3866875586241719de8d64160582ea303db0298
```

Core loading, shipped files, input parsing, activated-core dependency audit,
and Rails generator migration up/down pass. The dependency audit covers the
root lock and isolated activated core; it is not a claim about all OS packages
or every optional host dependency. These are local candidate checks, not a
published artifact or reproducible-build claim.

The final browser run is under ignored
`tmp/browser/2026-10-19T12-36-04-624Z-16077/`. It retains separate cancelled and
disconnected phase screenshots. Final process inspection finds no demo server,
no Playwright Chrome profile process, and no listener on port 3199. All worker
subprocesses are joined or terminated, and disposable databases are removed.


## Publication follow-up

On 2026-10-20, publication was separately authorized and completed:

- Tag `v0.3.0` points to `369057cd93fb1a27fc5f489073406a21f61a350c`.
- [Final candidate CI](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39376069591)
  passes all ten jobs. The preceding [matrix evidence](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39375830117)
  records Ruby 3.2.11, 3.3.12, and 3.4.11; Rails 8.0.5.1 and 8.1.4 on Ruby
  3.3/3.4; lint; installed-host checks; and browser workflows on Ubuntu 24.04.
- The initial Rails 8.0 jobs exposed JSON 3's removal of `quirks_mode` while
  loading a real RubyLLM chat. The same two intercepted-HTTP examples fail
  locally before the dependency bound and pass after it. JSON is constrained
  to 2.x in the published gem, with upgrade guidance. Both complete local
  Rails 8.0 and 8.1 suites pass 284 examples, zero failures, one provider skip.
- [Release verification and publishing](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39376258843)
  passes 284 examples, lint, 18 browser workflows, all 242 consumed-event schema
  checks, dependency audit, installed-host checks, and clean core/Rails checks.
- Linux browser evidence uses Playwright 1.64.1 and Chromium 156.0.8078.4.
  Desktop disconnection and 390px cancellation screenshots were inspected.
- [Stable docs deployment](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39376540516)
  builds v0.3.0 at `/` and main at `/next/`: 10,170 links in 150 pages, no errors.
  Public HTTP checks cover installation, upgrading, recovery, cancellation,
  client example, What's New, release history, both llms.txt channels, and
  RunRecord and Store::Base API pages. A browser verifies stable installation
  and switches to Next using the version menu; its screenshot was inspected.
- [GitHub Release](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.3.0)
  and [RubyGems](https://rubygems.org/gems/ruby_llm-ag_ui/versions/0.3.0)
  serve identical bytes. The downloaded files, RubyGems version metadata,
  GitHub asset digest, and `SHA256SUMS` agree:

```text
SHA256=9ed492bc2774b1acc91d75b5104f3ebfed2477aa3b0fba86d46e1ec53db541ed
```

The publishing job rebuilds the gem. The preceding verification job's artifact
has SHA-256 `605bca1edfe7e3d17263c944ee1eb5c6f602640bf03ad4f157f14bd9220c1cf6`,
so it does not establish the public bytes. The actual download is verified
again: all 62 packaged files match the tag; both installed endpoints and
RubyLLM models pass; fresh GEM_HOME core, activated dependency audit, and Rails
migration up/down pass. No reproducible-build claim is made.

The isolated macOS core activates JSON 2.7.1 and the remote matrix uses 2.21.2.
Root and activated-core audits report no findings against 1,266 advisories at
`fa2295251efb3b0d1a300e5ce8ad700ff1f1b485`. This does not audit all optional
host or OS dependencies. Fresh download evidence is under
`/var/folders/lg/2wcb539s3x79yz10zq8ltv1m0000gn/T/ag-ui-package-20261020-45725-pcrx45`.

Remote artifacts, public downloads, logs, and screenshots remain under ignored
`tmp/validation/` and `tmp/releases/v0.3.0/`. The hosted check closes its browser
in a finally block. No local server is started for publication, and all task
watch commands complete. No live provider is used. The next iteration is 0.4.0
API stabilization and recorded provider/dependency compatibility.
