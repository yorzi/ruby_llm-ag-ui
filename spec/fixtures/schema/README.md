# AG-UI 1.0 schema fixture

`ag-ui-1.0.schema.json` is a verbatim copy of
`docs/spec/1.0/schema.json` from the AG-UI repository at commit
`89cedd3fd549feeee41e50e1d7c6d373e549241a` (the same commit the gem pins in
`RubyLLM::AgUI::Protocol::SCHEMA_COMMIT`).

- Upstream: <https://github.com/ag-ui-protocol/ag-ui/blob/89cedd3fd549feeee41e50e1d7c6d373e549241a/docs/spec/1.0/schema.json>
- License: MIT (see `docs/_reference/third-party-notices.md`)
- SHA-256: `4b5c93226838a0e72d88e6c5df20633c686c49fcb75d9be2815c6cbf9e48e71a`

It is never edited here. To move to a newer schema commit, copy the file
again, update this note and `RubyLLM::AgUI::Protocol::SCHEMA_COMMIT`, and
re-run the conformance specs.
