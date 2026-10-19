# ruby_llm-ag_ui

[![CI](https://github.com/yorzi/ruby_llm-ag-ui/actions/workflows/ci.yml/badge.svg)](https://github.com/yorzi/ruby_llm-ag-ui/actions/workflows/ci.yml)

Connect [RubyLLM](https://rubyllm.com) chats to [AG-UI](https://docs.ag-ui.com)
clients over Server-Sent Events. The gem handles streaming text, tool calls, approval and resume,
cancellation outcomes, and run identity. Use it from plain Ruby or with the
optional Rails adapter.

Your application provides authentication, tool permissions, chat history, and
the model. This is an unofficial community project, independent of the
RubyLLM and AG-UI maintainers.

**[Documentation](https://rubyllm-ag-ui.wangyaodi.com/)** ·
[Getting started](https://rubyllm-ag-ui.wangyaodi.com/getting-started/) ·
[Rails guide](https://rubyllm-ag-ui.wangyaodi.com/rails-integration/) ·
[Compatibility](https://rubyllm-ag-ui.wangyaodi.com/compatibility/)

## Install

```ruby
gem 'ruby_llm-ag_ui', '~> 0.2.0'
```

Requires Ruby >= 3.2, RubyLLM >= 2.1 and < 3.0, and `ag-ui-protocol` 0.2.x.
Run `bundle install` after adding the gem.

## Stream a run

Pass a chat authorized for the current actor, a shared run store, and an
IO-like response stream from your application:

```ruby
require 'ruby_llm/ag_ui'

input = RubyLLM::AgUI::Input.parse(request_body)
chat = authorized_chat_for(current_user, input.thread_id)

RubyLLM::AgUI::Run.new(
  chat: chat,
  input: input,
  scope: "actor:#{current_user.id}",
  store: run_store
).stream(to: response_stream)
```

Build `scope` from authenticated identity. See the
[streaming guide](https://rubyllm-ag-ui.wangyaodi.com/streaming-runs/) for setup
and the [examples](examples/) for integration code.

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec rake example # offline approval and resume demo, no API key needed
```

The default suite is offline. Real client and provider verification is tracked
in the [compatibility guide](https://rubyllm-ag-ui.wangyaodi.com/compatibility/).
See [CONTRIBUTING.md](CONTRIBUTING.md) for development and documentation rules,
[ROADMAP.md](ROADMAP.md) for the proposed path to 1.0, and
[CHANGELOG.md](CHANGELOG.md) for shipped changes.

## License and security

[MIT](LICENSE.txt). See the
[third-party notices](https://rubyllm-ag-ui.wangyaodi.com/third-party-notices/)
and report vulnerabilities through [SECURITY.md](SECURITY.md).
