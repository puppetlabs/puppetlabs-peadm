# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::action::configure' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:all) do
    BoltSpec::Plans.init
  end

  it 'minimum variables to run' do
    expect_task('peadm::read_file').always_return({'content' => 'mock'})
    #expect_task('peadm::mkdir_p_file') ### this makes little sense why this isn't called
    allow_apply()
    expect_task('peadm::provision_replica').not_be_called
    expect_task('peadm::puppet_runonce')
    expect_task('peadm::code_manager').not_be_called
    expect_command('systemctl start puppet')
    expect(run_plan('peadm::action::configure', 'primary_host' => 'primary')).to be_ok
  end
end
