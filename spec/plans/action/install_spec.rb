# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::action::install' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:all) do
    BoltSpec::Plans.init
  end

  # something needs done here for the function

  it 'minimum variables to run' do
    allow_task('peadm::precheck').return_for_targets(
      'primary' => {
        'hostname' => 'primary',
        'platform' => 'el-7.11-x86_64'
      }
    )
    expect_task('peadm::mkdir_p_file').be_called_times(4)
    expect_plan('peadm::util::retrieve_and_upload')
    expect_task('peadm::read_file')
    expect_task('peadm::pe_install')
    expect_command('systemctl stop pe-puppetdb')
    expect_command('systemctl start pe-puppetdb')
    expect_task('peadm::rbac_token')
    expect_task('peadm::code_manager')
    expect_task('peadm::puppet_runonce').be_called_times(2)
    expect_task('peadm::wait_until_service_ready')
  #  expect(run_plan('peadm::action::install', 'primary_host' => 'primary', 'console_password' => 'puppetlabs')).to be_ok
#### Currently functions are not mockable in bolt testing as per 
#### https://github.com/puppetlabs/bolt/issues/1812 to work around us use
#### above testing you can comment out function peadm::file_content_upload
#### in the puppet code and uncomment the expect above to test and confirm
end
end