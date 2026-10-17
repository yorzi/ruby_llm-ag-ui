# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

desc 'Run the pure-Ruby smoke example and print the AG-UI event stream'
task :example do
  ruby 'examples/pure_ruby/app.rb'
end

task default: %i[spec rubocop]
