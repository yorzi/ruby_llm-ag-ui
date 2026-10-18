# Rails 8 integration example

These files show an actor-scoped AG-UI endpoint with an ActiveRecord run store.
They are integration templates, not a standalone Rails application. Follow the
[Rails guide](https://rubyllm-ag-ui.wangyaodi.com/rails-integration/) for the
adapter API, storage, and deployment details.

## Adapt to your application

1. Install `ruby_llm-ag_ui` before running `ruby_llm:ag_ui:install`. Install
   RubyLLM's chat models with `ruby_llm:install` if your app does not have them.
2. Adapt the models and controller in `app/`, then merge the route and
   initializer in `config/` into your application.
3. Adapt the two migrations in `db/migrate/`. Give them timestamps after the
   generated migration that creates `chats`, with `CreateActors` first.
   Run `bin/rails db:migrate`.
4. Configure your model and provider credentials through the host app. The
   endpoint resolves a host-owned chat; it does not append client messages to it.
   Add the authorized user turn in your host integration before expecting a
   response to the request's message.

`X-Actor` is a local demonstration of the scope boundary. Replace it with your
application's authentication before using this endpoint outside a local demo.
The files do not configure an approval tool or a complete browser client.

## Inspect the stream

Run your host with `bin/rails server -b 127.0.0.1`. In another terminal:

```sh
curl -N http://127.0.0.1:3000/agent \
  -H 'Content-Type: application/json' \
  -H 'Accept: text/event-stream' \
  -H 'X-Actor: demo' \
  -d '{"threadId":"thread-1","runId":"run-1","messages":[{"id":"m1","role":"user","content":"Hello"}]}'
```

`-N` disables curl buffering. Stop the Rails server with `Ctrl-C` when finished.

The repository's offline integration spec covers the Rails request path. It
does not establish that these files form a bootable app or that this example
works with a live provider. Fresh-app and client verification are planned in
[the 0.2.0 roadmap](../../ROADMAP.md#020-client-example-and-tool-progress).
