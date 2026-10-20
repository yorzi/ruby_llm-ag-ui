# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Exercise the lower and chosen current RubyLLM versions with separate locks.
gem 'ruby_llm', ENV.fetch('RUBY_LLM_VERSION', '>= 2.1.0')

group :development, :test do
  gem 'bundler-audit', '~> 0.9', require: false
  gem 'dotenv'
  gem 'json_schemer'
  gem 'puma', '>= 7', '< 9'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
  gem 'simplecov'
  gem 'webmock'

  # Rails is optional at runtime. It is loaded only by the adapter specs and the
  # examples, so the pure-Ruby core is verified without Rails. RAILS_VERSION
  # lets CI run the same suite against every supported Rails line.
  rails_version = ENV.fetch('RAILS_VERSION', '>= 8.0')
  gem 'actionpack', rails_version
  gem 'activerecord', rails_version
  gem 'railties', rails_version
  gem 'sqlite3'
end
