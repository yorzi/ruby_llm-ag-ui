# Security Policy

## Supported versions

The latest released minor version receives security fixes.

## Reporting a vulnerability

Do not open a public issue for a security problem. Use GitHub's private
vulnerability reporting on the repository
(<https://github.com/yorzi/ruby_llm-ag_ui/security/advisories/new>) or email the
maintainer at <andy@yorzi.me>.

Include, where possible:

- the affected version and Ruby/RubyLLM/`ag-ui-protocol` versions;
- a minimal reproduction, ideally without real credentials or model calls;
- whether untrusted input, an approval bypass, a duplicated side effect, or a
  leak into SSE or logs is involved.

You will get an acknowledgement within 7 days. Credit is offered unless you
prefer to stay anonymous.

## Security model

The threat model is documented in the [security and deployment guide](https://rubyllm-ag-ui.wangyaodi.com/security-and-deployment/). In
short: client-supplied `messages`, `state`, `tools`, `context` and
`forwardedProps` are untrusted and never grant host privileges or change host
policy; tool approvals and `resume` payloads are never permission grants; and
`RUN_ERROR` carries a sanitized message and code, never raw exception text.
