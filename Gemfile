# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'sqlite3'
  # Rails is optional at runtime. It is loaded only by the adapter specs and the
  # examples so the pure-Ruby core is verified without Rails.
  gem 'actionpack', '>= 8.0'
  gem 'activerecord', '>= 8.0'
  gem 'railties', '>= 8.0'
end
