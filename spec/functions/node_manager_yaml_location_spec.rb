# frozen_string_literal: true

require 'spec_helper'

# This function is loaded through Puppet's function loader
# (Puppet::Pops::Loader), not Ruby's `require` -- per
# documentation/test-coverage.md's SimpleCov section, this means
# SimpleCov/Ruby's Coverage module can never attribute this file's
# execution back to lib/puppet/functions/peadm/node_manager_yaml_location.rb.
# This spec still adds real regression coverage (it would catch a mutation
# to the join logic or filename), it just won't move the SimpleCov
# percentage.
describe 'peadm::node_manager_yaml_location' do
  # Catches a mutation that joins the wrong setting (e.g. :vardir instead
  # of :confdir) -- the expected value is computed independently here so
  # the assertion doesn't depend on (or go stale with) the test harness's
  # actual confdir default.
  it 'returns node_manager.yaml joined onto the real confdir setting' do
    expected = File.join(Puppet.settings['confdir'], 'node_manager.yaml')
    is_expected.to run.and_return(expected)
  end

  # Catches a mutation that hardcodes a different filename (e.g.
  # 'node-manager.yaml' or drops the .yaml extension).
  #
  # Puppet[:confdir] is global process state, so it's saved and restored
  # around the mutation -- leaving it changed would leak into later
  # examples and cause order-dependent failures.
  it 'returns node_manager.yaml joined onto a stubbed confdir' do
    original_confdir = Puppet[:confdir]
    begin
      Puppet[:confdir] = '/etc/puppetlabs/puppet'
      is_expected.to run.and_return('/etc/puppetlabs/puppet/node_manager.yaml')
    ensure
      Puppet[:confdir] = original_confdir
    end
  end
end
