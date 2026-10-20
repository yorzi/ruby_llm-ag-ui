# frozen_string_literal: true

require_relative 'lib/ruby_llm/ag_ui/version'

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-ag_ui'
  spec.version = RubyLLM::AgUI::VERSION
  spec.authors = ['Andy Wang']
  spec.email = ['andy@yorzi.me']

  spec.summary = 'Run RubyLLM chats as AG-UI 1.0 agent runs.'
  spec.description = <<~DESCRIPTION
    An unofficial RubyLLM ecosystem extension that turns one RubyLLM 2.x chat
    turn into one AG-UI 1.0 run. It parses and validates RunAgentInput, maps
    RubyLLM streaming, tool and lifecycle behavior onto schema-valid AG-UI
    events, turns requires_approval pauses into interrupt outcomes with
    host-authorized resume, reports cancellation as the cancelled outcome, and
    ships an SSE writer for plain Ruby plus an optional Rails adapter.
  DESCRIPTION

  spec.homepage = 'https://github.com/yorzi/ruby_llm-ag-ui'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['documentation_uri'] = 'https://rubyllm-ag-ui.wangyaodi.com/'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    # The generator templates are .rb.tt, so `lib/**/*.rb` would leave an
    # installed gem with no migration to install.
    # The docs site source is shipped as Markdown, but its built `_site/` output
    # is a deployment artifact and must not enter a gem built after a local site
    # build.
    Dir['lib/**/*.rb', 'lib/**/*.tt', 'docs/**/*.md', 'LICENSE.txt', 'README.md', 'CHANGELOG.md',
        'SECURITY.md', 'CONTRIBUTING.md'].reject { |path| path.start_with?('docs/_site/') }
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'ag-ui-protocol', '~> 0.2.0'
  spec.add_dependency 'ruby_llm', '>= 2.1', '< 3.0'
  # Rails 8.0 passes quirks_mode to JSON.generate when RubyLLM loads Chat.
  # JSON 3 removes that option. Keep both supported Rails lines usable.
  spec.add_dependency 'json', '>= 2.0', '< 3'

  # Old Ruby default gems can otherwise satisfy transitive dependencies while
  # retaining known URL, CGI, DNS and compression vulnerabilities.
  spec.add_dependency 'cgi', '>= 0.4.2', '< 1'
  spec.add_dependency 'resolv', '>= 0.7.2', '< 1'
  spec.add_dependency 'uri', '>= 1.0.4', '< 2'
  spec.add_dependency 'zlib', '>= 3.2.3', '< 4'
end
