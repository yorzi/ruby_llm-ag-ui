#!/usr/bin/env bash
# Build and preview the complete site, including its generated RDoc reference.
# Ctrl-C stops the server and removes its temporary build.
#   docs/bin/serve.sh        PORT=4002 docs/bin/serve.sh
set -euo pipefail

unset RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_BIN BUNDLE_APP_CONFIG

docs="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${PORT:-4000}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
site="$tmp/site"
root="$tmp/root"

if [[ -n "${BASE+x}" ]]; then
  base="$BASE"
else
  base="$(ruby -ryaml -e 'puts YAML.load_file(ARGV.fetch(0)).fetch("baseurl", "")' "$docs/_config.yml")"
fi
base="${base%/}"
if [[ -n "$base" && "$base" != /* ]]; then base="/$base"; fi

if [[ -n "${BASE+x}" ]]; then
  BASE="$base" SITE="$site" "$docs/bin/build.sh"
else
  SITE="$site" "$docs/bin/build.sh"
fi

if [[ -n "$base" ]]; then
  mkdir -p "$root$base"
  cp -a "$site/." "$root$base/"
  served="$root"
else
  served="$site"
fi

echo "Preview: http://127.0.0.1:$port${base}/"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$served"
