require 'spec_helper'

describe 'peadm::subplans::install' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  it 'minimum variables to run' do
    allow_any_task
    allow_any_plan
    allow_any_command

    allow_task('peadm::precheck').return_for_targets(
      'primary' => {
        'hostname' => 'primary',
        'platform' => 'el-7.11-x86_64'
      },
    )

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

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end
end
