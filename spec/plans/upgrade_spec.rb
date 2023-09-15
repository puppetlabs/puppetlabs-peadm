require 'spec_helper'

describe 'peadm::upgrade' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_apply
    allow_any_task
    allow_any_plan
    allow_any_command
    allow_out_message
  end

  let(:trusted_primary) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted-primary.json')))
  end

  let(:trusted_compiler) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted-compiler.json')))
  end

  it 'minimum variables to run' do
    allow_standard_non_returning_calls

    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })

    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary)

    expect(run_plan('peadm::upgrade',
                    'primary_host' => 'primary',
                    'version' => '2021.7.4')).to be_ok
  end

  it 'runs with a primary, compilers, but no replica' do
    allow_standard_non_returning_calls

    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })

    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary,
                                                       'compiler' => trusted_compiler)

    expect(run_plan('peadm::upgrade',
                    'primary_host' => 'primary',
                    'compiler_hosts' => 'compiler',
                    'version' => '2021.7.4')).to be_ok
  end

  it 'fails if the primary uses the pcp transport' do
    allow_standard_non_returning_calls

    result = run_plan('peadm::upgrade',
                      'primary_host' => 'pcp://primary.example',
                      'version' => '2021.7.1')

    expect(result).not_to be_ok
    expect(result.value.kind).to eq('unexpected-transport')
    expect(result.value.msg).to match(%r{The "pcp" transport is not available for use with the Primary})
  end

  context 'r10k_known_hosts' do
    let(:installed_version) { '2021.7.3' }
    let(:r10k_known_hosts) do
      [
        {
          'name'          => 'primary.rspec',
          'type'          => 'rsa',
          'key'           => 'pubkey',
        },
      ]
    end
    # NOTE: dupliating this error message is unfortunate, but
    # expect_out_message() doesn't take a regex.
    let(:r10k_warning) do
      <<~EOS
        \nWARNING: Starting in PE 2023.3, SSH host key verification is required for Code Manager and r10k.\n
        To enable host key verification, you must define the puppet_enterprise::profile::master::r10k_known_hosts parameter with an array of hashes containing "name", "type", and "key" to specify your hostname, key type, and public key for your remote host(s).\n
        If you currently use SSH protocol to allow r10k to access your remote Git repository, your Code Manager or r10k code management tool cannot function until you define the r10k_known_hosts parameter.\n
        Please refer to the Puppet Enterprise 2023.3 Upgrade cautions for more details.\n
      EOS
    end

    before(:each) do
      allow_standard_non_returning_calls

      expect_task('peadm::read_file')
        .with_params('path' => '/opt/puppetlabs/server/pe_build')
        .always_return({ 'content' => installed_version })

      expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary)
    end

    it 'updates pe.conf if r10k_known_hosts is set' do
      expect_task('peadm::read_file')
        .with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf')
        .always_return({ 'content' => <<~PECONF })
          # spec pe.conf
          "puppet_enterprise::puppet_master_host": "%{::trusted.certname}"
        PECONF
      # TODO: this doesn't verify what we are writing; we would need to mock
      # write_file for that. Being more specific about exactly what file we are
      # uploading runs afoul of the fact that write_file creates a source tempfile,
      # and we can't expect_upload() because we don't have the tempfile name.
      allow_any_upload

      expect(run_plan('peadm::upgrade',
                       'primary_host'     => 'primary',
                       'version'          => '2023.3.0',
                       'r10k_known_hosts' => r10k_known_hosts,
                       'permit_unsafe_versions' => true)).to be_ok
    end

    it 'warns if upgrading to 2023.3+ from 2023.0- without r10k_known_hosts set' do
      # This is fairly horrible, but expect_out_message doesn't take a regex.
      expect_out_message.with_params(r10k_warning)

      expect(run_plan('peadm::upgrade',
                       'primary_host'     => 'primary',
                       'version'          => '2023.3.0',
                       'permit_unsafe_versions' => true)).to be_ok
    end

    context 'upgrading from 2023.3+' do
      let(:installed_version) { '2023.3.0' }

      it 'does not warn if r10k_known_hosts is not set' do
        expect_out_message.with_params(r10k_warning).not_be_called

        expect(run_plan('peadm::upgrade',
                         'primary_host'     => 'primary',
                         'version'          => '2023.4.0',
                         'permit_unsafe_versions' => true)).to be_ok
      end
    end
  end
end
