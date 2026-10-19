# Offline client demo

The official `@ag-ui/client` consumes the gem's SSE through plain Ruby and
Rails endpoints. Chats and order effects are synthetic; no provider key is used.

```sh
bundle install
npm ci
npm run build:demo
bundle exec ruby examples/client/server.rb
```

Open <http://127.0.0.1:3199>. Use `Ctrl-C` to stop. The host creates and removes
its temporary SQLite database. `X-Demo-Actor` selects a fixture identity only;
replace that mechanism in a real application.

Run `bin/check-browser` for the automated workflows and fixture screenshots.
See the [client guide](https://rubyllm-ag-ui.wangyaodi.com/client-example/)
for details, limitations, and browser setup.
