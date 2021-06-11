# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::install' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:each) do
    BoltSpec::Plans.init
  end

  describe 'basic functionality' do
    it 'runs successfully with the minimum required parameters' do
      expect_plan('peadm::action::install')
      expect_plan('peadm::action::configure')
      expect(run_plan('peadm::install', 'primary_host' => 'primary', 'console_password' => 'puppetlabs')).to be_ok
    end
  end
end
