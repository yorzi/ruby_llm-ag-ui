# 0.4.0 validation

The candidate evidence below records the pre-publication state. Release
acceptance and public artifact verification follow it, with separate commits
and hashes.

Candidate: 2026-10-21, macOS arm64. Baseline `bdad5fb`; implementation commits
`d29d303`, `2678e5e`, and `14b3c15`. No public download was available at that stage.

## Changes and regression evidence

- Remove the inert history setting and reject unsupported protocol settings.
  Focused configuration tests fail before the change and pass afterward.
- Copy and freeze request, identity, interrupt, and JSON record values. Shared
  memory/SQLite tests reproduce mutable external identities and snapshots;
  parsed input and typed message mutation tests also fail before the fix.
  Frozen times serialize without mutating the timestamp to UTC.
- A real OpenRouter approval run reproduces a second tool-call start on resume.
  An intercepted-HTTP real RubyLLM chat reproduces the same defect. The fix
  continues original calls without another start/arguments/end; new calls
  still open. Results keep the original id. An exact retry of a completed
  resume executes no tool.
- Update the scripted example to fire the real resumed callback. Browser tests
  inspect official-client messages for one call and one associated result.
- Document application and store extension APIs, hide orchestration internals
  from RDoc, and separate opt-in provider verification from offline evidence.

## Results

| Check | Evidence |
| --- | --- |
| Local core | 294 examples, zero failures, two opt-in provider skips; 95 Ruby files without lint offenses |
| Minimum/current dependency | Separate full suites on RubyLLM 2.1.0 and 2.1.1, Ruby 3.3.5, Rails 8.1.4, JSON 2.21.2 |
| Remote matrix | [17 jobs pass](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39515383346) at `14b3c15`: Ruby 3.2.11/3.3.12/3.4.11, Rails 8.0.5.1/8.1.4, RubyLLM 2.1.0/2.1.1, lint, installed host, browser |
| Browser | 18 workflows and 242 schema-valid consumed events locally and remotely; ag-ui/client 1.0.3, Playwright 1.64.1; CI Chromium 156.0.8078.4 |
| Visual inspection | Local and remote desktop progress and 390px mobile denial screenshots inspected |
| Live session | OpenRouter / `openai/gpt-4.1-mini`, RubyLLM 2.1.1; two live cases plus one offline harness case pass with zero failures |
| Installed host | Both endpoints, approval, progress, reconnect, generated RubyLLM models, ordered migrations, actor-scoped chats pass |
| Clean environment | Core load, templates, parser, activated dependency audit, Rails generator and migration up/down pass on the same fixed artifact |
| Advisory database | 1,266 advisories at `5fd86bbd406995ea4ed2df84651b209e28072031`, no root or activated-core findings |
| Docs | 26 guides, no errors; two expected development warnings; [candidate deployment](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39515383320) checks 9,458 links in 145 pages with no errors |

## Fixed development artifact

All 66 packaged files match `14b3c15`. The installed-host and clean-environment
probes use the same gem built from that commit, with development dependencies and generated artifacts excluded:

```text
SHA256=b66e701b368d87aadf59fd7c4a175cb299bd5db1572d20b2405e31fd01cb23c9
```

Clean evidence: `/var/folders/lg/2wcb539s3x79yz10zq8ltv1m0000gn/T/ag-ui-package-20261021-9598-8i6uce`.
The isolated core activates JSON 2.7.1. Later documentation-only commits do not
make this a hash claim for a rebuilt gem. Repeat the release checks on the
actual publishable artifact before tagging.

## Limits and cleanup

The live fixture only returns synthetic data. It verifies Ruby streaming text,
approval, result association, default redaction, and exact completed-resume
reconnect on one model route. It does not establish live browser/Rails provider
sessions, denial, cancellation timing, timeouts, or network-loss behavior.
The first harness attempt was blocked by WebMock before reaching a provider;
the opt-in suite now allows only the OpenRouter HTTPS chat-completions URL.
No credentials or raw HTTP traces are committed.

SQLite is the verified database. Dependency resolver bounds are not proof for
future RubyLLM versions. The SDK check still finds no cancelled outcome or
protocol version on the upstream 0.2.0 models; local shims remain schema-tested.

Logs, screenshots, the temporary minimum-version bundle, and gems stay under
ignored `tmp/` and `pkg/`. Browser screenshots are under
`tmp/browser/2026-10-20T23-28-15-214Z-7197/`. The browser runner stops its
loopback server and browser on exit; no preview service needs to remain running.

## Release acceptance

Acceptance commit `e09b81b` adds two regressions: a completed reconnect exposes
the same observed record through `Run#stream` and `Run#record`, and a real
RubyLLM chat denies an interrupted tool without executing it. The record test
fails before the fix. Reconnect and public API guides change with that fix.
The installed-host probe now checks that resume emits one result for the
original call without another tool-call start, on both endpoints.

- `bin/check --package`: 296 examples, zero failures, two opt-in provider skips;
  95 Ruby files without lint offenses. Focused minimum/current RubyLLM runs pass.
- `bin/check-browser`: 18 workflows, 242 schema-valid events. Desktop approval
  progress and 390px Rails denial screenshots inspected under
  `tmp/browser/2026-10-21T00-01-09-075Z-17947/`.
- The release-code live rerun passes two OpenRouter text/approval cases plus
  one offline harness case. Denial is intercepted-HTTP evidence, not live evidence.
- [Acceptance CI](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39518735488)
  and [tag-source CI](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39518971268)
  each pass all 17 jobs. The latter runs at `23d9020`.

## Published artifact and documentation

Published on 2026-10-21. Annotated tag `v0.4.0` resolves to
`23d9020ffc34377f7e3e0c393c3baff217b36359`.
[Release Gem](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39519175592)
passes verification and trusted publication. The
[GitHub Release](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.4.0)
and [RubyGems version](https://rubygems.org/gems/ruby_llm-ag_ui/versions/0.4.0)
are available.

The verification job built `c9ee3ff728526996c2a48ae0720506b911fc0affb678de6c850b8679aeba7634`.
The publish job rebuilt the gem. The actual public gem has a different hash:

```text
SHA256=e98b51b3c3465af99ed894cb94689a16cbdb31107a92d7203250d454cdb4ddb8
```

The actual GitHub and RubyGems downloads are byte-identical. RubyGems metadata,
GitHub asset digest, and `SHA256SUMS` agree. The packaged manifest contains 66
files and every file matches the tag byte for byte. This establishes source
contents, not reproducibility of independently built gem archives.

The downloaded artifact, without rebuilding, passes both installed endpoints,
generated RubyLLM models, scoped chat persistence, and approval/progress/reconnect.
It independently passes a fresh core install, activated dependency audit, and
Rails 8.1.4 generator and migration up/down. Clean evidence:
`/var/folders/lg/2wcb539s3x79yz10zq8ltv1m0000gn/T/ag-ui-package-20261021-19953-8sfl4j`.
The audit uses the 1,266-advisory database at
`5fd86bbd406995ea4ed2df84651b209e28072031`, with no findings.

[Stable Docs](https://github.com/yorzi/ruby_llm-ag-ui/actions/runs/39519565224)
checks 8,748 links in 140 pages with zero errors and deploys successfully.
Fifteen actual HTTP content checks pass, including stable/Next installation
commands, upgrade and feature guides, generated API pages, and `llms.txt`.
A fresh Chrome session verifies stable 0.4.0 and the version menu's Next link;
`tmp/releases/v0.4.0/stable-docs.png` is visually inspected. The browser closes
on exit. All public check logs and downloaded artifacts remain ignored under
`tmp/releases/v0.4.0/` and `tmp/validation/`.

The next planned version is `1.0.0.rc.1`. Rehearse fresh applications and the
0.4 upgrade path, then review each 1.0 acceptance condition. Publication does
not establish live denial, cancellation, other providers, or non-SQLite stores.
