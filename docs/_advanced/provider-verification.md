---
layout: default
title: Provider Verification
nav_order: 6
description: Run opt-in provider checks separately from offline client and protocol tests.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to run the maintained live checks with synthetic input.
* What the checks verify and which calls can reach a provider.
* How to keep credentials and provider results out of shared evidence.

## Run the Opt-in Checks

From the repository, with `OPENROUTER_API_KEY` already configured:

```sh
RUBY_LLM_LIVE=1 bundle exec rspec spec/live
```

The harness uses OpenRouter with `openai/gpt-4.1-mini`. Set
`RUBY_LLM_LIVE_MODEL` to choose another OpenRouter model; record its name and
result separately. A successful model does not verify every model on the gateway.
These calls can incur provider charges. Default offline tests never run them.

If you use an environment file, keep it untracked and load it through dotenv:

```sh
RUBY_LLM_LIVE=1 bundle exec dotenv -f .env.live rspec spec/live
```

Set the key in that file or your existing credential manager. Do not put keys
in command arguments, inline exports, screenshots, or committed fixtures.
The repository ignores `.env*` files except `.env.example`.

## Understand the Checks

One example streams a short text response. Another forces a synthetic lookup
that requires approval, verifies no tool execution before approval, resumes the
original call, and reconnects the completed resume. The tool only returns a
fixture value; it does not access a database, file, or business service.
Its result is redacted and retains the original tool-call id.

The provider configuration disables retries, caps output at 128 tokens, uses
a 30-second request timeout, and discards provider logs. The live network
allowlist permits only the OpenRouter HTTPS chat-completions endpoint. This
allowlist is a test guard, not an operating-system firewall.

An offline test drives the same setup through intercepted HTTP. It verifies
the bounded request and reproduces the real RubyLLM approval callbacks without
credentials. Browser tests continue to use the maintained synthetic host; they
verify the official client's message and tool-result association separately.

## Record Evidence Without Secrets

Record the date, Ruby and RubyLLM versions, provider route, model, pass/fail
result, and any fixed regression. Keep generated evidence under ignored `tmp/`.
Do not save raw HTTP headers or provider traces. A failed assertion, intercepted
request, or schema-valid event is not proof that a live request completed.

For the recorded results and unverified paths, read
[Compatibility]({% link _reference/compatibility.md %}). Live cancellation,
timeouts, and network-loss timing require separate provider evidence; offline
fault injection does not establish those provider behaviors.
