# frozen_string_literal: true

require 'puppet'

if Gem::Version.new(Puppet.version) >= Gem::Version.new('6.0.0')
  begin
    require 'bolt_spec/plans'
    BoltSpec::Plans.init

    # Seems to be needed to make `run_plan` available inside examples:
    RSpec.configure { |c| c.include BoltSpec::Plans }
  rescue LoadError => e
    warn e.message
    warn '=== bolt tests will not run; ensure bolt gem is installed (requires Puppet 6+)'
  end
end

# Bolt has some hidden puppet modules inside the bolt codebase that need to be added here
# for proper testing and availablity with other tooling.  The code below will
# locate the bolt gem dir and create fixtures for each of the bolt modules.

spec = Gem::Specification.latest_specs.find { |s| s.name.eql?('bolt') }
bolt_modules = File.join(spec.full_gem_path, 'bolt-modules')
Dir.glob(File.join(bolt_modules, '*')).each do |dir|
  mod_name = File.basename(dir)
  mod_path = File.expand_path(File.join(__dir__, 'fixtures', 'modules', mod_name))
  FileUtils.ln_sf(dir, mod_path) unless File.exist?(mod_path)
end

RSpec.configure do |c|
  c.basemodulepath = bolt_modules
end
