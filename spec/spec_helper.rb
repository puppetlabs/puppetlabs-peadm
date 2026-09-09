# frozen_string_literal: true

RSpec.configure do |c|
  c.mock_with :rspec
end

require 'puppetlabs_spec_helper/module_spec_helper'
require 'rspec-puppet-facts'

require 'spec_helper_local' if File.file?(File.join(File.dirname(__FILE__), 'spec_helper_local.rb'))

include RspecPuppetFacts

default_facts = {
  puppetversion: Puppet.version,
  facterversion: Facter.version,
}

default_fact_files = [
  File.expand_path(File.join(File.dirname(__FILE__), 'default_facts.yml')),
  File.expand_path(File.join(File.dirname(__FILE__), 'default_module_facts.yml')),
]

default_fact_files.each do |f|
  next unless File.exist?(f) && File.readable?(f) && File.size?(f)

  begin
    default_facts.merge!(YAML.safe_load(File.read(f), permitted_classes: [], permitted_symbols: [], aliases: true))
  rescue StandardError => e
    RSpec.configuration.reporter.message "WARNING: Unable to load #{f}: #{e}"
  end
end

# read default_facts and merge them over what is provided by facterdb
default_facts.each do |fact, value|
  add_custom_fact fact, value
end

RSpec.configure do |c|
  c.default_facts = default_facts
  c.before :each do
    # set to strictest setting for testing
    # by default Puppet runs at warning level
    Puppet.settings[:strict] = :warning
    Puppet.settings[:strict_variables] = true
  end
  c.filter_run_excluding(bolt: true) unless ENV['GEM_BOLT']
  c.after(:suite) do
    RSpec::Puppet::Coverage.report!(0)
  end

  # Filter backtrace noise
  backtrace_exclusion_patterns = [
    %r{spec_helper},
    %r{gems},
  ]

  if c.respond_to?(:backtrace_exclusion_patterns)
    c.backtrace_exclusion_patterns = backtrace_exclusion_patterns
  elsif c.respond_to?(:backtrace_clean_patterns)
    c.backtrace_clean_patterns = backtrace_exclusion_patterns
  end
end

# Ensures that a module is defined
# @param module_name Name of the module
def ensure_module_defined(module_name)
  module_name.split('::').reduce(Object) do |last_module, next_module|
    last_module.const_set(next_module, Module.new) unless last_module.const_defined?(next_module, false)
    last_module.const_get(next_module, false)
  end
end

# 'spec_overrides' from sync.yml will appear below this line
# puppetlabs_spec_helper's module_spec_helper hardcodes SimpleCov.formatters to
# [HTMLFormatter, Console, Codecov] when ENV['SIMPLECOV'] == 'yes' (see
# `rake spec:simplecov`). Override it here to drop Codecov -- there's no
# CODECOV_TOKEN configured anywhere in this repo, so that formatter does nothing
# but attempt (and fail) a real network upload to codecov.io on every coverage run
# -- and add CoberturaFormatter instead, whose XML output CI uploads via GitHub's
# native code coverage feature.
if ENV['SIMPLECOV'] == 'yes'
  require 'simplecov-cobertura'

  SimpleCov.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Console,
    SimpleCov::Formatter::CoberturaFormatter,
  ]
end

# Ruby's Coverage library (which SimpleCov/CoberturaFormatter above rely on) can only
# instrument .rb files -- it can't measure coverage of Puppet manifests (.pp). rspec-puppet
# tracks its own "resource coverage" instead: which resources declared across compiled
# catalogs were touched by at least one example (see the `RSpec::Puppet::Coverage.report!`
# call above). Convert that per-resource data -- each resource carries its declaring file and
# line from the catalog -- into Cobertura XML, so manifest coverage rides the same GitHub
# code-coverage upload step as the Ruby coverage above.
#
# Caveat: this is resource-declaration-line coverage, not true statement coverage -- a .pp
# file with N declared resources gets N reported lines, not one per source line.
if ENV['SIMPLECOV'] == 'yes'
  require 'pathname'
  require 'rexml/document'

  RSpec.configure do |c|
    c.after(:suite) do
      collection = RSpec::Puppet::Coverage.instance.instance_variable_get(:@collection)
      repo_root = Pathname.new(Dir.pwd).realpath

      lines_by_file = Hash.new { |h, k| h[k] = Hash.new(0) }
      collection.each_value do |wrapper|
        resource = wrapper.resource
        next unless resource.file && resource.line

        begin
          relative_path = Pathname.new(resource.file).realpath.relative_path_from(repo_root).to_s
        rescue Errno::ENOENT
          next
        end
        next if relative_path.start_with?('..')

        lines_by_file[relative_path][resource.line] += wrapper.touched? ? 1 : 0
      end

      doc = REXML::Document.new
      doc << REXML::XMLDecl.new('1.0')
      doc.add(REXML::DocType.new(['coverage', 'SYSTEM', 'http://cobertura.sourceforge.net/xml/coverage-04.dtd']))

      total_lines = 0
      covered_lines = 0

      coverage_el = doc.add_element('coverage', 'version' => '0', 'timestamp' => Time.now.to_i.to_s)
      coverage_el.add_element('sources').add_element('source').text = '.'
      package_el = coverage_el.add_element('packages').add_element('package', 'name' => 'manifests')
      classes_el = package_el.add_element('classes')

      lines_by_file.sort.each do |file, lines|
        file_covered = lines.count { |_, hits| hits > 0 }
        total_lines += lines.size
        covered_lines += file_covered

        class_line_rate = lines.empty? ? 1.0 : file_covered.to_f / lines.size
        class_el = classes_el.add_element(
          'class', 'name' => File.basename(file), 'filename' => file, 'line-rate' => class_line_rate.to_s
        )
        class_el.add_element('methods')
        lines_el = class_el.add_element('lines')
        lines.sort.each do |line_number, hits|
          lines_el.add_element('line', 'number' => line_number.to_s, 'hits' => hits.to_s)
        end
      end

      overall_line_rate = (total_lines > 0) ? covered_lines.to_f / total_lines : 1.0
      coverage_el.add_attribute('line-rate', overall_line_rate.to_s)
      coverage_el.add_attribute('lines-covered', covered_lines.to_s)
      coverage_el.add_attribute('lines-valid', total_lines.to_s)
      package_el.add_attribute('line-rate', overall_line_rate.to_s)

      FileUtils.mkdir_p('coverage')
      File.write('coverage/puppet-coverage.xml', doc.to_s)
    end
  end
end
