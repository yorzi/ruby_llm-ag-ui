# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'dotenv'
  gem 'json_schemer'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
  gem 'simplecov'
  gem 'webmock'

  # Rails is optional at runtime. It is loaded only by the adapter specs and the
  # examples, so the pure-Ruby core is verified without Rails.
  gem 'actionpack', '>= 8.0'
  gem 'activerecord', '>= 8.0'
  gem 'railties', '>= 8.0'
  gem 'sqlite3'
end
