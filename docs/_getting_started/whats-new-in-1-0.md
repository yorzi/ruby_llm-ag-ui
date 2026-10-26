---
layout: default
title: "What's New in 1.0"
nav_order: -1
description: Try the 1.0 release candidate, with streamed tool calls fixed across provider protocols and a rehearsed upgrade from 0.4.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to try the release candidate and report a problem.
* Which streamed tool-call fixes reach your client.
* What changed for Rails boots, malformed input, and long-lived chats.

## Try the Release Candidate

Build and install the local gem using
[Candidate Acceptance]({% link _reference/release-candidate.md %}).
Version 1.0.0.rc.1 is not published or tagged. It freezes features for 1.0
and keeps the public API and store contract that 0.4 proposed, with no new
migration. Repeat the affected checks after a fix. After maintainer acceptance,
the next planned publication is 1.0.0. Report a problem
with the versions from `RubyLLM::AgUI.config.to_h`, as
[Compatibility]({% link _reference/compatibility.md %}) describes.

## Stream Tool Calls Correctly Across Protocols

A client assembles a tool call's arguments by joining its `TOOL_CALL_ARGS`
deltas. Before this release, three provider shapes produced arguments the client
could not parse or attribute:

* A second tool round in one turn sent its arguments to the first round's ended
  call. Chat Completions, OpenAI Responses, and Anthropic restart stream indexes
  in every response.
* Anthropic and Bedrock open a call with an empty input object before streaming
  partial JSON, so the client received `{}{"query":"one"}`.
* Gemini sends a whole call as a parsed object, which went out as Ruby
  `Hash#to_s` output instead of JSON.

Each call now opens once, and its deltas join to the JSON arguments the tool
received. Intercepted-HTTP specs run a real RubyLLM chat for Chat Completions,
Responses, Anthropic, and Gemini. Bedrock uses the same empty-object rule
without its own HTTP spec. See [Streaming Runs]({% link _core_features/streaming-runs.md %}).

## Boot Rails Without Loading Active Record Early

Requiring the gem during `Bundler.require` no longer loads `ActiveRecord::Base`.
The durable store's row class loads on first use, after your application's
configuration. The generated initializer still assigns
`RubyLLM::AgUI::Rails::ActiveRecordStore.new` as before.

## Refuse an Unacceptable Stream Before Provider Work

`SSEWriter.accepts?` honors quality values and media-range precedence. An
explicit `text/event-stream;q=0` refuses SSE even with `*/*;q=1`. Empty media
parameters do not raise a server error. Rails returns 406 before resolving a
chat or reserving a run. Stream conflicts also return 409 in Rails hosts that
do not load Active Record; unrelated host errors still propagate.

## Refuse Malformed Text as a Client Error

```ruby
RubyLLM::AgUI::Input.parse(body)
# => raises RubyLLM::AgUI::MalformedInputError (400)
```

A body whose text is not UTF-8, or that holds a number JSON cannot represent,
is now refused as malformed input. The Rails adapter answers 400 instead of
raising `JSON::GeneratorError` as a server error.

## Reuse a Chat Across Turns

RubyLLM cannot remove a callback, so each run's callbacks stay on a chat you
reuse. A finished run now releases its response stream, and its callbacks map
and write nothing. A redaction policy object that defines only `#call` also
works now, alongside lambdas and methods.

## Upgrade From 0.4

Change the version in your Gemfile and run `bundle update ruby_llm-ag_ui`.
Records written by 0.4 stay readable. The release rehearsal reconnects to a 0.4
run and resumes a 0.4 interrupt with the candidate. Follow
[Upgrading]({% link _reference/upgrading.md %}) for the steps.

## Next Steps

* [Compatibility]({% link _reference/compatibility.md %}) - read the release candidate evidence.
* [Public API Contract]({% link _reference/public-api.md %}) - review the API 1.0 stabilizes.
* [Release History]({% link _reference/release-history.md %}) - compare earlier releases.
