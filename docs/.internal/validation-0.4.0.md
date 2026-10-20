# 0.4.0 development candidate

2026-10-21, macOS arm64. Baseline `bdad5fb`; implementation commits `d29d303`,
`2678e5e`, and `14b3c15`. Version 0.4 is unreleased. No tag, RubyGems upload,
or public 0.4 download is claimed.

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
