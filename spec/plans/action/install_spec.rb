require 'spec_helper'

describe 'peadm::action::install' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  it 'minimum variables to run' do
    allow_task('peadm::precheck').return_for_targets(
      'primary' => {
        'hostname' => 'primary',
        'platform' => 'el-7.11-x86_64'
      },
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

    #########
    ## <🤮>
    # rubocop:disable AnyInstance
    allow(Tempfile).to receive(:new).and_call_original
    allow(Pathname).to receive(:new).and_call_original
    allow(Puppet::FileSystem).to receive(:exist?).and_call_original
    allow_any_instance_of(BoltSpec::Plans::MockExecutor).to receive(:module_file_id).and_call_original

    mockfile = instance_double('Tempfile', path: '/mock', write: nil, flush: nil, close: nil, unlink: nil)
    mockpath = instance_double('Pathname', absolute?: true)
    allow(Tempfile).to receive(:new).with('peadm').and_return(mockfile)
    allow(Pathname).to receive(:new).with('/mock').and_return(mockpath)
    allow(Puppet::FileSystem).to receive(:exist?).with('/mock').and_return(true)
    allow_any_instance_of(BoltSpec::Plans::MockExecutor).to receive(:module_file_id).with('/mock').and_return('/mock')

    allow_upload('/mock')
    # rubocop:enable AnyInstance
    ## </🤮>
    ##########

    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetlabs',
    }

    expect(run_plan('peadm::action::install', params)).to be_ok
  end
end
