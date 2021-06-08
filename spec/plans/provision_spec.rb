# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::provision' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:all) do
    BoltSpec::Plans.init
  end


  it 'minimum variables to run' do
    expect_plan('peadm::action::install')
    expect_plan('peadm::action::configure')
    expect(run_plan('peadm::provision', 'primary_host' => 'primary', 'console_password' => 'puppetlabs')).to be_ok
  end
end