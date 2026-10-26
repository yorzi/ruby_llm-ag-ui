# Roadmap to 1.0

Sequence reviewed on 2026-10-26. Versions 0.2, 0.3, and 0.4 are published.
1.0.0.rc.1 is a local, unpublished candidate. After automated verification and
the maintainer's real installation tests, the next planned publication is 1.0.0.
Later releases remain targets rather than promised dates. Keep one release in
progress. Split or drop optional work when it delays the release's main outcome;
use patch releases for fixes.

## What 1.0 means

You can connect a RubyLLM chat to a verified AG-UI client, stream text and tool
calls, approve or deny a tool, cancel a run through the host, and reconnect to
its recorded outcome. The plain Ruby and Rails paths have reproducible examples.
The public API and supported dependency ranges have evidence behind them.

1.0 stabilizes this integration contract. It does not require producing every
AG-UI event type. Conversation history, authentication, tool permissions, and
the model remain the host application's responsibility.

## Starting point

The offline suite covers input validation, event order, terminal outcomes,
approval/resume, run identity, and the memory and ActiveRecord stores. The
repository defines Ruby and Rails CI matrices and package verification.
These checks do not establish real client or live provider compatibility.

[0.2.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.2.0) is published
on 2026-10-19. The initial gaps now have reproducible checks:

- `@ag-ui/client` 1.0.3 consumes both plain Ruby and Rails streams in Chrome.
  Browser workflows and captured-event schema checks run with one command.
- The live spec now supplies `scope:`; its setup also runs against an offline
  chat. A live provider session remains unverified and is not a 0.2 claim.
- The installed-artifact host checks generator/migration and run paths. It also
  generates RubyLLM's models and tables and verifies the Rails example's ordered
  migrations and actor-scoped persisted chats. The complete client demo retains
  synthetic chats per actor/thread in one process.

See [Compatibility](docs/_reference/compatibility.md) for the evidence boundary.
Remote CI, the release workflow, the published artifact checks, and the stable
documentation deployment pass. These remain separate from live-provider evidence.

## Release sequence

Each release has one main outcome. Fixes and documentation belong with the
behavior they describe; future features stay out of the changelog until built.

| Version | Main outcome | Release condition |
| --- | --- | --- |
| **0.2.0 (released)** | A real client example and opt-in tool progress | A pinned client consumes the demo; progress is ordered, redacted, and schema-valid. |
| **0.3.0 (released)** | Reliable lifecycle and durable runs | Disconnect, cancellation, worker loss, and competing requests have tested, documented outcomes. |
| **0.4.0 (released)** | Compatibility and API stabilization | The proposed 1.0 support matrix and public API pass end-to-end verification. |
| **1.0.0.rc.1 (prepared)** | Release rehearsal | A fresh application uses the packaged candidate without checkout-only files or undocumented setup. |
| **1.0.0** | Stable integration contract | All release conditions below pass; no known blocker remains. |

### 0.2.0: client example and tool progress

Keep this to one new gem feature and the example needed to exercise it.

- [x] Fix the live spec setup and verify the Rails example's installation path.
  Persist the host's chat between requests so a second turn and an approval
  resume use the same conversation.
- [x] Add a minimal example using a pinned `@ag-ui/client` and a scripted Ruby
  backend. It runs without provider credentials and shows text, a tool call,
  approval/denial, and a second turn. Record exact versions and commands.
  If the client rejects the pinned protocol shapes, resolve that mismatch
  before expanding the example or claiming interoperability.
- [x] Add opt-in tool progress from RubyLLM's `after_tool_progress(tool_call,
  progress)` callback. The installed RubyLLM 2.1.1 exposes this callback, but
  `Run#drive` currently registers only tool-call, message, and text callbacks.
  The implementation uses replacing `ACTIVITY_SNAPSHOT` events with stable
  per-call identity. Its payload and redaction policy are documented in
  [Tool Progress](docs/_core_features/tool-progress.md).
- [x] Test unknown totals, message-only updates, concurrent tool progress, default
  redaction, and late callbacks after the run closes. Progress must not
  change approval behavior or the single terminal outcome.
- [x] Add a discoverable progress guide, update protocol coverage and What's New,
  and record the tested client version in Compatibility. A real-client demo
  against a scripted chat is still not live-provider evidence.

Do not add activity deltas, state mutation, a UI framework, or a broker in
this release. The progress feature remains a small callback mapping.

### 0.3.0: lifecycle and storage reliability

- [x] Test disconnects before the first event, during a tool, and around terminal
  persistence. Define what remains in the store and what a retry receives.
- [x] Document and verify host-triggered cancellation and provider timeouts.
  Client HTTP abort and server-side `Chat#cancel` are separate actions; show
  the host wiring required to connect them. Keep cancellation scope-bound.
- [x] Exercise competing reservations and approval redemptions through independent
  database connections or workers. Start with SQLite, the current tested store
  backend. A sequential store test is not evidence of a cross-worker race.
- [x] Define recovery for a worker that dies with a non-terminal run. Keep it
  explicit and host-controlled. Never automatically rerun a tool whose side
  effect is unknown, or claim exactly-once execution across crashes.

Publish the supported recovery procedure and its limits. A background job
system, resumable provider execution, and live stream fan-out remain outside
the gem.

The 2026-10-19 local candidate passes 284 examples and 18 real-client browser
workflows. Independent-process SQLite tests include a producer killed after
a synthetic tool effect and synchronized writes from the same observed payload.
Storage acknowledgement failures preserve uncertain outcomes instead of guessing
success or failure. Guides describe the changed custom-store contract and the
requirement to drain old workers. The 2026-10-20 remote matrix passes after
excluding JSON 3, which is incompatible with Rails 8.0.
[0.3.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.3.0) is published
on 2026-10-20. Release verification, matching public downloads, fresh core/Rails
installation, and stable documentation checks pass.

### 0.4.0: compatibility and API stabilization

- [x] Name the public API to freeze: input parsing, `Run`, configuration, store
  contract, error/status behavior, Rails hooks, and progress added earlier.
  Mark internals and resolve ineffective settings such as the reserved
  `allow_client_history` option before treating them as supported switches.
- [x] Run the client through success, tool results, approval, denial, cancellation,
  sanitized failure, and completed-run reconnect. Verify the resumed tool
  result is associated with the original call and text is not duplicated.
- [x] Record at least one live provider/model for text, a tool call, and approval
  resume through the gem. Add a second provider only if its support is claimed.
  Keep credentials out of traces; record failures as well as successful runs.
- [x] Test the minimum and chosen current RubyLLM versions within the supported
  range, plus the declared Ruby/Rails matrix. Narrow any unverified range or
  label it clearly. Verify PostgreSQL/MySQL only if adding a support claim.
- [x] Recheck upstream SDK gaps against the chosen dependency versions. Remove a
  local workaround only after replacement behavior passes the same tests.

The 2026-10-21 candidate defines the public API and custom-store contract,
removes an unused history switch, and refuses unsupported protocol settings.
Read-only request and record values now isolate nested JSON and run identity.
A real provider session exposed duplicate resumed tool-call events; intercepted
HTTP, browser client state, and a passing OpenRouter approval session verify
the fix. The remote 17-job Ruby/Rails/RubyLLM matrix passes. Installed-package,
fresh core/Rails, advisory, browser, and docs checks pass separately. See
[Compatibility](docs/_reference/compatibility.md) for versions and limits.
Release acceptance adds reconnect record consistency, real-chat denial, and
installed-artifact result association. The 296-example suite, 17-job matrix,
and rerun live text/approval checks pass.
[0.4.0](https://github.com/yorzi/ruby_llm-ag-ui/releases/tag/v0.4.0) is published
on 2026-10-21. The actual GitHub and RubyGems downloads match, all 66 packaged
files match the tag, and the downloaded artifact passes installed-host and
fresh core/Rails checks. Stable and Next documentation pass HTTP and browser
checks, including the version selector.

### 1.0.0.rc.1: release rehearsal

Freeze features. Build and install the candidate artifact into fresh plain Ruby
and Rails applications. Run the documented client and provider paths, verify
generator files and migrations, and rehearse upgrading from the last 0.x release.
Repeat affected acceptance checks when a fix changes public behavior. Keep the
candidate unpublished. Publish 1.0 only after the maintainer accepts the real
installation, without using a calendar deadline as the gate.

- [x] Audit the mapper, run lifecycle, stores, input parsing, and Rails adapter
  against RubyLLM 2.1.1's real provider protocols.
- [x] Fix each confirmed defect with a failing test first: streamed tool calls
  in a second tool round, Anthropic/Bedrock empty opening input, Gemini whole
  call arguments, early Active Record loading, non-UTF-8 input as a server
  error, call-only redaction policies, and retained streams on reused chats.
- [x] Build the candidate and pass installed-host, clean core/Rails, advisory,
  browser, and live OpenRouter checks.
- [x] Rehearse the upgrade from the published 0.4.0 artifact: 0.4 records
  reconnect and resume, and the generated files are unchanged.
- [ ] Pass the final remote matrix and review the fixed local artifact.
- [ ] Complete the maintainer's real application installation and upgrade tests
  using [Candidate Acceptance](docs/_reference/release-candidate.md). Do not
  tag or publish an RC. Prepare 1.0.0 only after this acceptance.

The 2026-10-21 local rehearsal is recorded in
[Compatibility](docs/_reference/compatibility.md). The streamed tool-call
defects affected Chat Completions, OpenAI Responses, Anthropic, Bedrock, and
Gemini; the 0.4 evidence did not exercise two tool rounds or those shapes.
Intercepted-HTTP specs now run a real RubyLLM chat for each tested shape.

The 2026-10-26 review adds pre-stream HTTP refusal tests and a real Rails host
without Active Record, and makes the two-artifact 0.4 upgrade probe repeatable
in CI. Ruby and client advisory checks are refreshed. The browser client uses
patched Zod with the same 18 passing workflows. The candidate remains local;
the maintainer's real application installation is still pending.

## 1.0 release conditions

- [ ] The claimed text, tool, approval, denial, cancellation, failure, progress,
  and reconnect paths pass against the recorded client and provider versions.
- [ ] Run identity, tenant isolation, approval replay/expiry, redaction, event
  order, and concurrent store operations have positive and negative tests.
- [ ] Worker-loss and transport-failure behavior is explicit, tested, and does
  not silently re-execute side effects.
- [ ] The declared dependency matrix passes CI. Local tests, remote CI, client
  checks, and live-provider checks are recorded as separate evidence.
- [ ] The public API is documented, examples work from the installed artifact,
  and breaking changes have upgrade steps.
- [ ] Package, advisory, and documentation checks in the
  [release guide](docs/_reference/releasing.md) pass. Version, changelog,
  What's New, and published documentation agree when the release is published.

Do not publish 1.0 with an unresolved duplicate-execution, authorization,
sensitive-output, terminal-outcome, or advertised-client compatibility defect.

## Deferred until a concrete use case

State mutation/deltas, message-history reconstruction, reasoning exposure,
subagent events, client-supplied tool execution, Redis stores, job orchestration,
and live delta replay are not 1.0 requirements. Add one only when a reproducible
host need fits this gem's integration boundary.

## Next action

Complete the final remote checks and hand the fixed local candidate artifact to
the maintainer for real application testing. Keep features frozen and record
the exact artifact hash with the results. Resolve any reported defect, repeat
the affected checks, then prepare and publish 1.0.0 after acceptance. Keep RC
tags and publication disabled. Live evidence for a second provider is needed
only if 1.0 claims one.
