---
layout: default
title: Client Example
nav_order: 3
description: Run a real AG-UI browser client against offline Ruby and Rails endpoints.
---

# {{ page.title }}

{{ page.description }}
{: .fs-6 .fw-300 }

After reading this guide, you will know:

* How to run the maintained offline client example.
* Which interactions it verifies with the official client.
* Which responsibilities remain with a real host application.

## Run the Example

From the repository, install the development dependencies and build the client:

```sh
bundle install
npm ci
npm run build:demo
bundle exec ruby examples/client/server.rb
```

Open `http://127.0.0.1:3199`. Stop the server with `Ctrl-C` when finished.
The host binds loopback and serves only the demo HTML and its locally bundled
JavaScript. It creates and removes a temporary SQLite database on each run.
No CDN, provider account, or API key is needed.

Choose **Plain Ruby** or **Rails + SQLite**, then run a turn. The official
`@ag-ui/client` package consumes the SSE stream. The scripted host retains one
chat per fixture actor and thread, so approval resumes the original tool call
and later turns use the same conversation.

The development bundle pins `@ag-ui/client` 1.0.3 and overrides Zod to 4.6.6
for [GHSA-mrhx-c7xc-m3w5](https://github.com/advisories/GHSA-mrhx-c7xc-m3w5).
The client and core schema code import `zod/v4`; browser workflows verify the
override with the pinned client. Run `npm audit` alongside the browser checks.
These JavaScript packages are development dependencies and are not shipped in
the Ruby gem.

## Try the Interactions

The tool scenario pauses for approval. Approve it to run a synthetic order
cancellation once, or deny it to leave the order unchanged. Tool results stay
redacted by default. Approved tools also publish synthetic progress counts;
the host policy withholds progress messages. The text, sanitized failure, and cancelled scenarios show
the other run outcomes.

During approved progress, **Cancel server run** requests cancellation for the
exact fixture actor, thread, and run. The host rejects another actor, an old
run id, or a completed run. The synthetic tool checks cancellation before its
effect. This does not establish cancellation latency for a real provider or
arbitrary tool.

**Disconnect stream** calls the client's HTTP abort. The producer keeps running
and records its actual outcome. Reconnect after it finishes to read that result
without repeating the tool. An early reconnect is refused while the host still
owns the active chat. The timeout scenario produces a sanitized recorded failure.

Use **Reconnect completed run** after a successful turn. The client sends the
original input and receives the recorded outcome and snapshot; no new model
turn or text delta is produced.

## Check in a Browser

```sh
bin/check-browser
```

This runs Playwright with Chrome or its installed Chromium. On Linux, install
the browser first with `npx playwright install --with-deps chromium`. Set
`CHROME_BIN` to select another local Chrome executable.

The check starts its own server, runs desktop and 390px mobile scenarios, saves
screenshots and consumed events under ignored `tmp/browser/`, and stops the
server and browser. It validates the captured events against the pinned JSON
schema. Failures retain traces and screenshots. Inspect those artifacts before
retrying; a screenshot alone is not an assertion.

## Verify an Installed Gem

```sh
bin/check --package
```

The package probe builds a gem, installs that artifact outside the checkout,
and checks both run paths, generated migration, approval, progress, and
reconnect. It also generates RubyLLM's models and tables, applies the Rails
example migrations in order, and checks actor-scoped chat persistence. It uses
available development dependencies. Use `bin/verify-package --rails --audit`
after `bundle exec rake build` to resolve dependencies in a clean gem home.

## Adapt to a Real Host

The example's actor header is a synthetic identity selector. It does not
provide authentication, CSRF protection, or durable chat history. The run store
uses SQLite, but the scripted chat objects live in one process and disappear
when that process stops. A real host authorizes the thread and the next user
turn, persists its RubyLLM chat, and rechecks tool permission before execution.

The demo and browser suite make no live provider call. Read
[Compatibility]({% link _reference/compatibility.md %}) for the exact versions
and evidence boundaries.

## Next Steps

* [Rails Integration]({% link _advanced/rails-integration.md %}) - install the adapter in your application.
* [Approval and Resume]({% link _core_features/approval-and-resume.md %}) - inspect the resume contract.
