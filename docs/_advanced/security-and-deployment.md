---
layout: default
title: "Security and Deployment"
nav_order: 2
description: Keep identity, tool permissions, and sensitive output under the host application's control.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* Which values the gem treats as untrusted.
* How redaction, error sanitization, and interrupt redemption work.
* Which security decisions the host application must make.

This gem is a **producer**, not an authorization layer. It decides what a run may
report on the wire and refuses what it cannot report truthfully. It does not
decide who may run what: authentication, authorization, which tools and model an
actor may use, and whether a tool may execute are the host's decisions.

The model below is the one the test suite enforces, and the negative cases are
fixtures, not prose. If a claim here has no test, it is marked as host
responsibility.

## Trust boundaries

| Input | Trusted? | Why |
|---|---|---|
| `messages`, `state`, `tools`, `context`, `forwardedProps` | **No** | Arbitrary JSON from the client. Accepted as data only. |
| `threadId`, `runId`, `parentRunId`, `resume` | **No** | They name things; they never select a record or grant a right. |
| `protocolVersion` | **No** | Reported and compared; an unknown version is refused, not honored. |
| The `scope` string | **Yes, because the host built it** | It must come from authenticated identity. The gem rejects a non-String or empty scope. |
| The `chat` object | **Yes** | The host constructed it, with the host's tools and model. |
| Tool output | **No** | A tool reads databases, APIs and files. Its payload can hold secrets and personal data. |
| Provider exceptions | **No** | They can embed request bodies, URLs, headers and keys. |
| The run store | **Yes** | Host infrastructure. |

## What a client cannot do

- **Choose the model, tools or system prompt.** `input.tools` is informational:
  `Input#tool_names` and `Input#client_tools?` report it, and nothing in the gem
  registers a client-supplied tool on the chat. `input.messages` is parsed and
  echoed, never appended to the chat as trusted turns; `config.allow_client_history`
  is off and documented as off.
- **Reach another actor's run.** Every lookup is bounded by the scope the host
  supplies. The same `(threadId, runId)` under a different scope is a different
  run (`spec/ruby_llm/ag_ui/run_spec.rb`: "does not let one scope attach to
  another tenant run").
- **Redeclare a run id.** The same identity with a *different* input is refused
  as `RunConflictError` (409 in the Rails adapter) rather than executed
  ("refuses the same identity with a changed input as a conflict").
- **Run the same tool twice.** A resume is recorded once; a new run that answers the
  same interrupt is refused without executing the tool ("refuses a decision
  another resume already recorded, without executing the tool").
- **Widen what an approval covers.** An interrupt pins the tool call and the
  digest of the arguments RubyLLM asked to run. A resume whose call arguments
  changed, whose call is no longer pending, or which names an interrupt that
  expired or does not exist is refused before anything is reserved or written
  ("refuses a resume whose tool call arguments changed since the interrupt",
  "refuses an expired interrupt", "refuses an unknown interrupt before the run is
  reserved or opened").
- **Inject SSE framing.** Every frame is one JSON document on one `data:` line;
  a payload containing newlines stays inside the JSON string. There is no path
  that writes a raw payload into a frame.
- **Exhaust the process with one body.** The body is bounded before it is parsed
  (`max_input_bytes`, 256 KB default), and so are message, tool and context
  counts.

## Redaction is the default

`config.redact` defaults to `RubyLLM::AgUI::Redaction.method(:default)`: the
payload keeps its **shape** and loses its **content** (`[redacted]`), because the
gem cannot know which part of a tool result is a secret. The mapper warns once per
run that the host has not chosen a policy
(`spec/ruby_llm/ag_ui/mapper_spec.rb`: "keeps the shape and withholds the
content", "warns once that the host has not chosen a policy").

Opting out is explicit:

```ruby
RubyLLM::AgUI.configure do |config|
  config.redact = RubyLLM::AgUI::Redaction.method(:none)   # publish as-is
  # or
  config.redact = ->(kind, payload) { MyPolicy.call(kind, payload) }
end
```

A `nil` policy is not an opt-out: `Configuration#redact` falls back to the
default, so a mistyped configuration cannot publish raw payloads. What is in
force is reported by `RubyLLM::AgUI.config.to_h[:redact]` as `:default`, `:none`
or `:custom`.

Redaction applies to what the gem publishes. It does not scrub the host's logs,
the chat's own history, the provider's copy of the conversation, or any payload
the host writes to the wire by other means.

## Errors never carry exception text

`RUN_ERROR` is built from `ErrorSanitizer`: a fixed message and code per error
class, and a fixed `internal_error` fallback for anything unrecognized. The raw
exception goes to the host logger, if one is configured, and nowhere else
(`spec/ruby_llm/ag_ui/run_spec.rb`: "never echoes the exception text";
`spec/ruby_llm/ag_ui/error_sanitizer_spec.rb`).

This matters because upstream Rails examples put `e.message` straight into the
event. A provider error message can contain the prompt, the tool arguments, a URL
with a key in it, or an internal path.

## Interrupts

An interrupt is a pause, not a permission. It carries the tool call id, a reason,
a human-readable question, and a host-owned expiry. It does **not** carry the
arguments digest that the resume check uses ("does not let the arguments digest
reach the client"), so the client cannot forge a matching approval.

- TTL is `config.interrupt_ttl` (900 s default) or per-run `expires_in:`.
- An expired interrupt is not answerable; a resume for it is refused.
- A resume with `status: "cancelled"` records a denial. The chat's next
  `complete` reports the denial as RubyLLM normally would; no tool runs.
- Approval does not skip the host's re-authorization: the host re-checks before
  a tool executes, and the gem cannot do it for them.

The store's redemption step is the concurrency guard: the first decision wins and
is recorded, the loser is told it was already recorded. That is why an approved
tool executes once even when two resumes arrive together.

## Reconnect

A run that already ended is served from its record: `RUN_STARTED` (with the
protocol version and the input echo), `STATE_SNAPSHOT` when one was recorded, and
the recorded terminal event. Deltas are never replayed, and a run that has not
ended is refused rather than attached ("refuses to attach a second stream to a run
that has not ended"). Both rules exist to prevent a duplicated side effect, not
just duplicated text.

A recorded failure is reported with the sanitized message and code it was stored
with. A record with no recorded failure reports `internal_error` rather than
guessing.

## Transport

The gem writes to whatever object the host gives it and sets no security policy
of its own beyond the framing. The Rails adapter adds:

- `Accept` negotiation: a client that cannot read `text/event-stream` gets 406
  before any event.
- Input refusal before the response commits: 400, 404, 409, 413, never a
  half-open stream.
- `Content-Type: text/event-stream`, `Cache-Control: no-cache`,
  `Connection: keep-alive`, `X-Accel-Buffering: no`.
- A client disconnect is swallowed: it is not a run outcome.

The gem does not terminate TLS, authenticate, rate-limit, validate Origin/CSRF
for browser clients, or configure CORS. Those are the host's, and getting them
wrong is outside what this gem can detect.

## Deployment checklist

1. Authenticate before parsing the body; build `scope` from the authenticated
   actor, never from anything in the body.
2. Authorize the `threadId → chat` lookup inside the actor's own association, so
   a client-chosen id cannot select somebody else's conversation.
3. Re-authorize before an approved tool runs. An approval answers an interrupt;
   it does not grant permission.
4. Use a durable store with a uniqueness constraint on
   `(scope, thread_id, run_id)` and `(scope, thread_id, interrupt_id)`. The Rails
   store is built for that; `MemoryStore` is single-process only.
5. Keep redaction on until you have classified which payloads may be published.
   Scrub raw bodies, prompts and tool payloads out of your logs.
6. Treat `messages`, `state` and `forwardedProps` as untrusted text in any UI you
   build. Escape it where it is rendered; a producer cannot prevent XSS.
7. Bound the resource: request size (`max_input_bytes`), provider timeouts, rate
   limits, and the number of concurrent streams (an `ActionController::Live`
   response holds a thread for the run's lifetime).
8. Serve over TLS, and set CORS and cookie policy deliberately if the stream is
   consumed from a browser.
9. Do not enable client-supplied tools for a multi-tenant deployment in this
   release; they are never used, and that is the intended behavior.
10. Do not log the request body or the events at info level.

## What is out of scope

- **Prompt injection.** Content that arrives in `messages`, tool results or
  documents can steer a model. This gem maps the model's behavior faithfully; it
  cannot make the model trustworthy.
- **Host authentication and authorization**, including whether a given actor
  should be allowed to run a given tool.
- **Provider-side data handling**, retention and training.
- **Anything the host writes outside the gem's events**, such as its own log lines,
  its own extra SSE frames, its own UI.
- **Denial of service by an authenticated actor** who opens many legitimate
  streams.

## Reporting

See the [repository security policy](https://github.com/yorzi/ruby_llm-ag-ui/blob/main/SECURITY.md) for the reporting process. Reports about a silent duplicate execution, an approval that widens what it covers, a secret in a `RUN_ERROR`, or a leak into the log are treated as vulnerabilities.

## Next Steps

* [Configuration]({% link _getting_started/configuration.md %}) - set safe redaction and storage defaults.
* [Rails Integration]({% link _advanced/rails-integration.md %}) - apply these boundaries in a controller.
