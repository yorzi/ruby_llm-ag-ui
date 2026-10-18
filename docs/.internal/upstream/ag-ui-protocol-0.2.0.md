# Upstream issue drafts — `ag-ui-protocol` 0.2.0

The Ruby SDK models the AG-UI types, but five things this gem needs are missing
or wrong. Each draft below is ready to file at
<https://github.com/ag-ui-protocol/ag-ui/issues>; none has been filed yet, so no
issue number is claimed here.

| ID | Title | Affects | Severity |
|---|---|---|---|
| [SDK-GAP-01](#sdk-gap-01) | `RunFinishedEvent` cannot express the 1.0 `cancelled` outcome | Any producer that cancels | Blocks a schema-valid terminal event |
| [SDK-GAP-02](#sdk-gap-02) | `RunStartedEvent` has no `protocolVersion` | Every 1.0 producer | Blocks declaring the protocol version |
| [SDK-GAP-03](#sdk-gap-03) | No JSON → `RunAgentInput` parser | Every server-side Ruby host | Forces hand-written validation |
| [SDK-GAP-04](#sdk-gap-04) | `SUBAGENT_STARTED` / `_FINISHED` / `_ERROR` are missing | Producers with subagents | Three 1.0 events cannot be typed |
| [SDK-GAP-05](#sdk-gap-05) | Five legacy `THINKING_*` constants are still exported | Every consumer of `EventType` | Looks like 1.0 coverage; is not |

The 1.0 schema these refer to is pinned at commit
`89cedd3fd549feeee41e50e1d7c6d373e549241a`
(`docs/spec/1.0/schema.json`).

---

## SDK-GAP-01

**Title:** `RunFinishedEvent` cannot express the 1.0 `cancelled` outcome

**Labels:** `bug`, `protocol`, `ruby-sdk`

**Body:**

The 1.0 schema defines three `RunFinishedOutcome` shapes:

- `RunFinishedSuccessOutcome` (`{"type": "success"}`)
- `RunFinishedInterruptOutcome` (`{"type": "interrupt", "interrupts": [...]}`)
- `RunFinishedCancelledOutcome` (`{"type": "cancelled"}`)

`ag-ui-protocol` 0.2.0 models only the first two:

```ruby
require 'ag_ui_protocol'
AgUiProtocol::Core::Events.constants.grep(/Outcome/)
# => [:RunFinishedSuccessOutcome, :RunFinishedInterruptOutcome]
```

`RunFinishedEvent`'s `outcome:` parameter is typed as one of those two, so a
Ruby producer that stopped a run (a user pressed stop, a budget ran out, a
deadline passed) cannot construct a schema-valid terminal event. The workarounds
are all wrong: reporting `success` claims work that did not happen, reporting
`interrupt` invents something to wait for, and omitting `outcome` means success.

**Expected:** a `RunFinishedCancelledOutcome` model with `type: "cancelled"`,
accepted by `RunFinishedEvent`.

**Actual:** no such constant; `RunFinishedEvent.new(outcome: ...)` raises a
Sorbet type error for a `cancelled` hash.

**Suggested fix:** add

```ruby
class RunFinishedCancelledOutcome < AgUiProtocol::Core::Types::Model
  sig { returns(String) }
  attr_reader :type   # always "cancelled"
  # ...
end
```

and widen `RunFinishedEvent#outcome` to the three-way union. A minimal
reproduction of the gap is in `ag_ui_protocol/core/events.rb` around the
`RunFinishedSuccessOutcome` / `RunFinishedInterruptOutcome` definitions.

---

## SDK-GAP-02

**Title:** `RunStartedEvent` has no `protocolVersion`

**Labels:** `bug`, `protocol`, `ruby-sdk`

**Body:**

`RUN_STARTED` in the 1.0 schema carries `protocolVersion`, so a consumer can
detect a producer built for an older or newer protocol. The Ruby SDK's
`RunStartedEvent` accepts `thread_id`, `run_id`, `parent_run_id`, `input`,
`timestamp` and `raw_event`, and has no `protocol_version` field:

```ruby
require 'ag_ui_protocol'
AgUiProtocol::Core::Events::RunStartedEvent
  .instance_method(:initialize).parameters.map(&:last)
# => [:thread_id, :run_id, :parent_run_id, :input, :timestamp, :raw_event]
```

Because it subclasses a closed model, a producer cannot add the field: passing an
unknown keyword fails validation and the encoder drops it from `to_h`. Producers
therefore emit a `RUN_STARTED` that cannot declare its version — exactly the
downgrade signal the field exists to provide.

**Expected:** `RunStartedEvent.new(..., protocol_version: "1.0")` encodes
`"protocolVersion": "1.0"`.

**Actual:** no keyword, no property, no way to comply.

**Suggested fix:** add an optional `protocol_version` attribute (default `"1.0"`)
and include it in `to_h` when present. This is additive and does not change any
existing event's shape.

**Note on the workaround:** subclassing `RunStartedEvent` and overriding `to_h`
works, but only because the SDK's model validation is bypassed by the subclass.
A consumer that validates against the schema will accept the output; a consumer
that uses the SDK's own types will not see the field at all.

---

## SDK-GAP-03

**Title:** No JSON → `RunAgentInput` parser, so every server re-implements validation

**Labels:** `feature`, `ruby-sdk`, `security`

**Body:**

The SDK can model `RunAgentInput` and encode events. It cannot go the other way:
there is no `RunAgentInput.from_h`, no `parse`, and no schema validation
(`grep -rn "def self.from\|JSON.parse\|def parse" lib/` finds nothing in 0.2.0).

Every Ruby host that accepts a `RunAgentInput` over HTTP therefore writes the same
code by hand: read a bounded body, parse JSON, check required members, validate
message shapes, check array sizes, strip or reject unknown members, and produce
something typed. Hand-written versions of this are where the usual bugs live —
an unbounded body, a `threadId` trusted from the client, a `runId` that is not a
string, messages that pass through as trusted turns.

**Expected:** something equivalent to

```ruby
input = AgUiProtocol::Core::Types::RunAgentInput.parse(json, max_bytes: 256_000)
input.thread_id # => "thread-1"
```

raising a typed error whose message contains no request bytes.

**Actual:** constructors and `to_h` only.

**Suggested fix:** a `parse` (or `from_json`) that validates against the pinned
schema and raises a dedicated error class, plus a documented size bound. If a
full validator is out of scope, a `from_h` that checks member types and required
keys would still remove most of the duplication.

---

## SDK-GAP-04

**Title:** `SUBAGENT_STARTED`, `SUBAGENT_FINISHED` and `SUBAGENT_ERROR` are missing from the SDK

**Labels:** `bug`, `protocol`, `ruby-sdk`

**Body:**

The 1.0 schema defines three subagent events, with `SubagentStartedEvent`,
`SubagentFinishedEvent`, `SubagentErrorEvent` and companion types
(`SubagentFinishedOutcome`, `SubagentFinishedSuccessOutcome`,
`SubagentFinishedSuspendedOutcome`). The Ruby SDK's `EventType` exports none of
them:

```ruby
require 'ag_ui_protocol'
AgUiProtocol::Core::Events::EventType.constants.grep(/SUBAGENT/)
# => []
```

So a Ruby producer that runs subagents cannot emit a typed event for one, and a
Ruby consumer cannot dispatch on one. The set of event types a Ruby client can
handle is silently smaller than the protocol it claims to speak.

**Expected:** the three event models and their `EventType` constants.

**Actual:** neither the constants nor the models exist.

**Suggested fix:** port the three event types from the schema, and add them to
whatever registry the encoder dispatches through.

---

## SDK-GAP-05

**Title:** Five legacy `THINKING_*` constants are exported but are not 1.0 events

**Labels:** `bug`, `protocol`, `ruby-sdk`

**Body:**

`EventType` exports 33 constants. The 1.0 schema defines 31 event types. The extra
five are legacy names that no 1.0 consumer should ever receive:

```ruby
require 'ag_ui_protocol'
AgUiProtocol::Core::Events::EventType.constants.grep(/THINKING/)
# => [:THINKING_TEXT_MESSAGE_START, :THINKING_TEXT_MESSAGE_CONTENT,
#     :THINKING_TEXT_MESSAGE_END, :THINKING_START, :THINKING_END]
```

The difference matters in both directions:

- A producer can emit them, and they will look like valid protocol events while
  being invalid 1.0 ones. Any coverage audit that counts `EventType` constants
  reports 33/31, which is the wrong number.
- A consumer that switches on `EventType` gets a larger set than the schema, and
  a `THINKING_*` case that can never be reached from a conforming producer.

**Expected:** `EventType` is exactly the 1.0 set (plus the three subagent types
from SDK-GAP-04, once added).

**Actual:** five legacy constants present; the three current subagent types
absent.

**Suggested fix:** mark the five as deprecated and remove them in the next major,
or move them to a `LegacyEventType` module. If they are kept for compatibility,
say so in the README and in the constant list so audits can exclude them.

---

## Why this matters for this gem

`ruby_llm-ag_ui` works around all five:

- `Protocol::CancelledOutcome` and `Protocol::RunFinishedEvent` (subclassing
  `BaseEvent`, not the SDK's event) for SDK-GAP-01.
- `Protocol::RunStartedEvent` for SDK-GAP-02.
- `Input.parse` and its parser for SDK-GAP-03.
- Nothing to emit for SDK-GAP-04, because RubyLLM 2.x runs one chat.
- An explicit `Coverage` map that excludes the legacy types for SDK-GAP-05.

If upstream closes a gap, the corresponding workaround should be deleted rather
than kept for compatibility: two ways to express one event shape is exactly the
kind of drift this project is trying not to add.
