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
