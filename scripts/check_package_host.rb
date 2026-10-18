# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'rubygems/installer'
require 'rubygems/package'
require 'tmpdir'
require_relative '../lib/ruby_llm/ag_ui/version'

def prepare_artifact(root, artifact)
  if ARGV.include?('--built')
    source = File.join(root, "pkg/ruby_llm-ag_ui-#{RubyLLM::AgUI::VERSION}.gem")
    abort 'Build the artifact first: bundle exec rake build' unless File.file?(source)

    FileUtils.cp(source, artifact)
  else
    abort 'gem build failed' unless system(RbConfig.ruby, '-S', 'gem', 'build', 'ruby_llm-ag_ui.gemspec',
                                           '--output', artifact, chdir: root)
  end
end

root = File.expand_path('..', __dir__)
Dir.mktmpdir('ag-ui-installed-host-') do |workspace|
  artifact = File.join(workspace, 'candidate.gem')
  prepare_artifact(root, artifact)
  package = Gem::Package.new(artifact)
  package.verify
  abort 'development artifacts in package' if package.contents.any? do |file|
    file.match?(%r{(?:\A|/)(?:\.internal|node_modules|tmp|_site)(?:/|\z)|\.(?:sqlite3|png|key)\z})
  end
  home = File.join(workspace, 'gems')
  specification = Gem::Installer.at(artifact, install_dir: home, ignore_dependencies: true, document: []).install
  expected = File.join(specification.full_gem_path, 'lib/ruby_llm/ag_ui.rb')
  environment = {
    'GEM_HOME' => home, 'GEM_PATH' => ([home] + Gem.path).join(File::PATH_SEPARATOR),
    'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLE_GEMFILE' => nil, 'BUNDLE_BIN_PATH' => nil,
    'EXPECTED_ENTRYPOINT' => expected
  }
  output, error, result = Open3.capture3(environment, RbConfig.ruby,
                                         File.join(root, 'scripts/packaged_host_probe.rb'), chdir: workspace)
  FileUtils.mkdir_p(File.join(root, 'tmp/validation'))
  File.write(File.join(root, 'tmp/validation/package-host.log'), output + error)
  abort output + error unless result.success?

  puts output.lines.grep(/PASS|VERSIONS/).join
  puts "PACKAGE_HOST_SHA256=#{Digest::SHA256.file(artifact).hexdigest}"
end
