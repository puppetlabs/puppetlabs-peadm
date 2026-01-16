require 'spec_helper'

describe 'peadm::subplans::install' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  before(:each) do
    allow_any_task
    allow_any_plan
    allow_any_command

    allow_task('peadm::precheck').return_for_targets(
      'primary' => {
        'hostname' => 'primary',
        'platform' => 'el-7.11-x86_64',
      },
      'compiler1' => {
        'hostname' => 'compiler1',
        'platform' => 'el-7.11-x86_64',
      },
      'compiler2' => {
        'hostname' => 'compiler2',
        'platform' => 'el-7.11-x86_64',
      },
    )

    #########
    ## <🤮>
    # rubocop:disable RSpec/AnyInstance
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
    # rubocop:enable RSpec/AnyInstance
    ## </🤮>
    ##########
  end

  it 'minimum variables to run' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2019.8.12',
    }

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  it 'installs 2023.4 without r10k_known_hosts' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.4.0',
      'r10k_remote' => 'git@github.com:puppetlabs/nothing',
      'r10k_private_key_content' => '-----BEGINfoo',
    }

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  it 'installs 2023.4+ with r10k_private_key and r10k_known_hosts' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.4.0',
      'r10k_remote' => 'git@github.com:puppetlabs/nothing',
      'r10k_private_key_content' => '-----BEGINfoo',
      'r10k_known_hosts' => [
        {
          'name' => 'test',
          'type' => 'key-type',
          'key' => 'abcdef',
        },
      ],
      'permit_unsafe_versions' => true,
    }

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  it 'installs 2023.8.8 with legacy compilers' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.8',
      'legacy_compilers' => ['compiler1', 'compiler2'],
    }
    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end
end
