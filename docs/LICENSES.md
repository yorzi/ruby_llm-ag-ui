# Licenses and third-party notices

`ruby_llm-ag_ui` is released under the MIT License. See
[`LICENSE.txt`](../LICENSE.txt).

It is an unofficial community project. It is not affiliated with, endorsed by, or
maintained by the RubyLLM maintainers or the AG-UI protocol maintainers.

## Runtime dependencies

| Project | License | How this gem uses it |
|---|---|---|
| [RubyLLM](https://github.com/crmne/ruby_llm) | MIT | The agent loop this gem projects: `Chat#complete`, the streaming block, `before_tool_call`, `after_message`, approval state and cancellation. |
| [ag-ui-protocol](https://github.com/ag-ui-protocol/ag-ui) (Ruby SDK, `~> 0.2.0`) | MIT | Event models, `BaseEvent`, the encoder and the event-type constants. |
| [Zeitwerk](https://github.com/fxn/zeitwerk) | MIT | Autoloading the gem's own files. |

The gem's direct runtime dependencies are `ruby_llm` and `ag-ui-protocol`.
Zeitwerk arrives through RubyLLM and is used directly.

## Optional: Rails

Rails is **not** a runtime dependency. When a host already has it, the adapter
uses:

| Project | License |
|---|---|
| [Rails](https://github.com/rails/rails) (`railties`, `actionpack`, `activerecord`) | MIT |
| [SQLite3](https://github.com/sparklemotion/sqlite3-ruby) (development/test only) | BSD-3-Clause |

## Vendored file

`spec/fixtures/schema/ag-ui-1.0.schema.json` is a verbatim copy of
`docs/spec/1.0/schema.json` from the AG-UI repository at commit
`89cedd3fd549feeee41e50e1d7c6d373e549241a`.

- Upstream: <https://github.com/ag-ui-protocol/ag-ui/blob/89cedd3fd549feeee41e50e1d7c6d373e549241a/docs/spec/1.0/schema.json>
- License: MIT (the AG-UI repository's `LICENSE` at the same commit)
- SHA-256: `4b5c93226838a0e72d88e6c5df20633c686c49fcb75d9be2815c6cbf9e48e71a`
- Provenance note: [`spec/fixtures/schema/README.md`](../spec/fixtures/schema/README.md)

It is used only by the test suite and is never served, re-published or modified.

## Development dependencies

None of these are shipped to users.

| Project | License |
|---|---|
| RSpec | MIT |
| RuboCop, `rubocop-rake`, `rubocop-rspec` | MIT |
| `json_schemer` | MIT |
| WebMock | MIT |
| SimpleCov | MIT |
| dotenv | MIT |
| Rake | MIT |

## What this gem does not include

No code, templates, assets or schema from ToolViews, OpenUI, OddlyDock or any
AG-UI client is bundled, copied or required. No provider SDK is vendored: RubyLLM
supplies provider access, and this gem never talks to a provider directly.

## Names and trademarks

"RubyLLM" and "AG-UI" are used only to describe what this gem extends. Neither
project's name, logo or maintainers are used to imply endorsement. The gem is
published as `ruby_llm-ag_ui` under the author's own name and namespace
(`RubyLLM::AgUI`), and it does not define or reopen the top-level `AgUi`
namespace owned by the `ag-ui` gem.
