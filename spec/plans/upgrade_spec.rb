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

  let(:pe_rule_check) do
    {
      'updated' => 'true',
    'message' => 'a message'
    }
  end

  it 'minimum variables to run' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })

    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })

    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary).be_called_times(1)
    expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
    expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })

    expect(run_plan('peadm::upgrade',
                    'primary_host' => 'primary',
                    'version' => '2021.7.9')).to be_ok
  end

  it 'runs with a primary, compilers, but no replica' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })

    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })
    expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary,
                                                       'compiler' => trusted_compiler).be_called_times(1)
    expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check).be_called_times(1)

    expect(run_plan('peadm::upgrade',
                    'primary_host' => 'primary',
                    'compiler_hosts' => 'compiler',
                    'version' => '2021.7.9')).to be_ok
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

  # PE-45737: no existing test ever makes check_pe_master_rules return
  # 'updated' => false. If the `unless $rules_check['updated'] { fail_plan(...) }`
  # guard at plans/upgrade.pp:152-155 were removed or inverted, an operator
  # upgrading a cluster whose PE Master group rules haven't been migrated by
  # the Convert plan would silently proceed instead of being stopped with a
  # clear instruction to run Convert first.
  it 'fails if the PE Master rules have not been updated to support pe_compiler_legacy' do
    allow_standard_non_returning_calls
    expect_task('peadm::check_pe_master_rules').always_return(
      'updated' => false,
      'message' => 'PE Master rules need to be updated to support pe_compiler_legacy',
    )

    result = run_plan('peadm::upgrade',
                      'primary_host' => 'primary',
                      'version' => '2021.7.9')

    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{run the Convert plan})
  end

  # PE-45737: this fail_plan (plans/upgrade.pp:171-183) is never exercised by
  # any existing test because every cert_data fixture in this file has fully
  # populated peadm_role/pp_auth_role/peadm_availability_group values. Here the
  # primary's cert has the peadm_role and pp_auth_role trusted extensions
  # present but with nil values (as would happen with a legacy/partially
  # provisioned node), which must trip the "Required trusted facts are not
  # present" guard rather than being silently treated as valid.
  it 'fails when required trusted facts are present but empty' do
    trusted_primary_missing_facts = {
      'certname' => 'primary',
      'extensions' => {
        '1.3.6.1.4.1.34380.1.3.39' => 'true',
        '1.3.6.1.4.1.34380.1.1.9812' => nil, # peadm_role OID, present but empty
        'pp_auth_role' => nil,               # present but empty
        '1.3.6.1.4.1.34380.1.1.9813' => 'A',
      },
      'dns-alt-names' => ['puppet'],
    }

    allow_standard_non_returning_calls
    expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary_missing_facts).be_called_times(1)
    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })
    expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })

    result = run_plan('peadm::upgrade',
                      'primary_host' => 'primary',
                      'version' => '2021.7.9')

    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{Required trusted facts are not present})
  end

  # PE-45737: no existing test ever sets final_agent_state to anything but the
  # default 'running', so a mutation that swapped the 'start'/'stop' ternary
  # branches at plans/upgrade.pp:450-453 (or dropped the 'stopped' case
  # entirely) would go undetected. This asserts the finalize step issues a
  # 'stop' action, not 'start', when final_agent_state => 'stopped'.
  it 'stops (rather than starts) the puppet agent service when final_agent_state is stopped' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })
    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })
    expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary).be_called_times(1)
    expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)

    expect_task('service')
      .with_targets(['primary'])
      .with_params('action' => 'stop', 'name' => 'puppet')
      .be_called_times(1)

    expect(run_plan('peadm::upgrade',
                    'primary_host' => 'primary',
                    'version' => '2021.7.9',
                    'final_agent_state' => 'stopped')).to be_ok
  end

  # PE-45737: the compiler DR availability-group split (plan lines ~186-208)
  # determines which compilers get upgraded alongside the primary
  # (compiler_m1_targets, matched against the primary's availability group)
  # versus alongside the replica (compiler_m2_targets, matched against the
  # replica's availability group). No existing test combines a replica with
  # more than one compiler, so nothing currently catches the m1/m2 filters
  # being built from the wrong side of the pair (e.g. $replica_target[0]
  # swapped for $primary_target[0], or vice versa), which would send
  # compilers to the wrong upgrade step or upgrade the same compilers twice.
  context 'DR availability-group compiler split' do
    let(:trusted_replica) do
      {
        'certname' => 'replica',
        'extensions' => {
          '1.3.6.1.4.1.34380.1.3.39' => 'true',
          '1.3.6.1.4.1.34380.1.1.9812' => 'puppet/replica',
          '1.3.6.1.4.1.34380.1.1.9813' => 'B',
        },
        'dns-alt-names' => ['puppet'],
      }
    end

    let(:trusted_compiler_group_a) do
      {
        'certname' => 'compiler',
        'extensions' => {
          'pp_auth_role' => 'pe_compiler',
          '1.3.6.1.4.1.34380.1.3.13' => 'pe_compiler',
          '1.3.6.1.4.1.34380.1.1.9813' => 'A',
        },
        'dns-alt-names' => ['puppet'],
      }
    end

    let(:trusted_compiler_group_b) do
      {
        'certname' => 'compiler',
        'extensions' => {
          'pp_auth_role' => 'pe_compiler',
          '1.3.6.1.4.1.34380.1.3.13' => 'pe_compiler',
          '1.3.6.1.4.1.34380.1.1.9813' => 'B',
        },
        'dns-alt-names' => ['puppet'],
      }
    end

    it 'upgrades group-A compilers with the primary and group-B compilers with the replica' do
      allow_standard_non_returning_calls
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })
      expect_task('peadm::read_file')
        .with_params('path' => '/opt/puppetlabs/server/pe_build')
        .always_return({ 'content' => '2021.7.3' })
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
      expect_task('peadm::cert_data').return_for_targets(
        'primary'   => trusted_primary,
        'replica'   => trusted_replica,
        'compiler1' => trusted_compiler_group_a,
        'compiler2' => trusted_compiler_group_a,
        'compiler3' => trusted_compiler_group_b,
        'compiler4' => trusted_compiler_group_b,
      ).be_called_times(1)

      # Group A: upgraded alongside the primary, in upgrade-primary-compilers
      expect_task('peadm::puppet_infra_upgrade')
        .with_targets(['primary'])
        .with_params('type' => 'compiler', 'targets' => ['compiler1', 'compiler2'], 'token_file' => nil,
                     'wait_until_connected_timeout' => 120)
        .be_called_times(1)

      # The replica itself, in upgrade-replica
      expect_task('peadm::puppet_infra_upgrade')
        .with_targets(['primary'])
        .with_params('type' => 'replica', 'targets' => ['replica'], 'token_file' => nil,
                     'wait_until_connected_timeout' => 120)
        .be_called_times(1)

      # Group B: upgraded alongside the replica, in upgrade-replica-compilers
      expect_task('peadm::puppet_infra_upgrade')
        .with_targets(['primary'])
        .with_params('type' => 'compiler', 'targets' => ['compiler3', 'compiler4'], 'token_file' => nil,
                     'wait_until_connected_timeout' => 120)
        .be_called_times(1)

      expect(run_plan('peadm::upgrade',
                      'primary_host' => 'primary',
                      'replica_host' => 'replica',
                      'compiler_hosts' => ['compiler1', 'compiler2', 'compiler3', 'compiler4'],
                      'version' => '2021.7.9')).to be_ok
    end
  end

  # PE-45737: the `puppetdb delete-reports` workaround (plan lines ~405-437) is
  # gated on `$arch['disaster-recovery'] and $_version >= 2019.8`; neither half
  # of this AND has any existing coverage. These tests catch either condition
  # being dropped, inverted, or turned into an OR.
  context 'delete-reports workaround' do
    let(:pdbapps) { '/opt/puppetlabs/server/apps/puppetdb/cli/apps' }

    # Exact text of the heredoc-rendered commands at plan lines ~412-417 and
    # ~430-435, confirmed by rendering the same heredoc syntax with `puppet
    # apply` and capturing its output.
    let(:workaround_command) do
      "if [ -e #{pdbapps}/delete-reports -a ! -h #{pdbapps}/delete-reports ]\n" \
      "then\n" \
      "  mv #{pdbapps}/delete-reports #{pdbapps}/delete-reports.original\n" \
      "  ln -s $(which true) #{pdbapps}/delete-reports\n" \
      "fi\n"
    end

    let(:restore_command) do
      "if [ -e #{pdbapps}/delete-reports.original ]\n" \
      "then\n" \
      "  mv #{pdbapps}/delete-reports.original #{pdbapps}/delete-reports\n" \
      "fi\n"
    end

    let(:trusted_replica) do
      {
        'certname' => 'replica',
        'extensions' => {
          '1.3.6.1.4.1.34380.1.3.39' => 'true',
          '1.3.6.1.4.1.34380.1.1.9812' => 'puppet/replica',
          '1.3.6.1.4.1.34380.1.1.9813' => 'B',
        },
        'dns-alt-names' => ['puppet'],
      }
    end

    before(:each) do
      allow_standard_non_returning_calls
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)
    end

    it 'moves delete-reports aside and restores it after the replica upgrade on a DR architecture, version >= 2019.8' do
      expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary, 'replica' => trusted_replica).be_called_times(1)
      expect_task('peadm::read_file')
        .with_params('path' => '/opt/puppetlabs/server/pe_build')
        .always_return({ 'content' => '2021.7.3' })

      expect_command(workaround_command).with_targets(['replica']).be_called_times(1)
      expect_command(restore_command).with_targets(['replica']).be_called_times(1)

      expect(run_plan('peadm::upgrade',
                      'primary_host' => 'primary',
                      'replica_host' => 'replica',
                      'version' => '2021.7.9')).to be_ok
    end

    it 'does not touch delete-reports on a DR architecture upgrading to a version < 2019.8' do
      expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary, 'replica' => trusted_replica).be_called_times(1)
      expect_task('peadm::read_file')
        .with_params('path' => '/opt/puppetlabs/server/pe_build')
        .always_return({ 'content' => '2018.1.10' })

      expect_command(workaround_command).not_be_called
      expect_command(restore_command).not_be_called

      expect(run_plan('peadm::upgrade',
                      'primary_host' => 'primary',
                      'replica_host' => 'replica',
                      'version' => '2019.7.9')).to be_ok
    end

    it 'does not touch delete-reports on a non-DR (no replica) architecture even at version >= 2019.8' do
      expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary).be_called_times(1)
      expect_task('peadm::read_file')
        .with_params('path' => '/opt/puppetlabs/server/pe_build')
        .always_return({ 'content' => '2021.7.3' })

      expect_command(workaround_command).not_be_called
      expect_command(restore_command).not_be_called

      expect(run_plan('peadm::upgrade',
                      'primary_host' => 'primary',
                      'version' => '2021.7.9')).to be_ok
    end
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

      expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary).be_called_times(1)
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })
    end

    it 'updates pe.conf if r10k_known_hosts is set' do
      expect_task('peadm::read_file')
        .with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf')
        .always_return({ 'content' => <<~PECONF }).be_called_times(2)
          # spec pe.conf
          "puppet_enterprise::puppet_master_host": "%{::trusted.certname}"
        PECONF
      # TODO: this doesn't verify what we are writing; we would need to mock
      # write_file for that. Being more specific about exactly what file we are
      # uploading runs afoul of the fact that write_file creates a source tempfile,
      # and we can't expect_upload() because we don't have the tempfile name.
      allow_any_upload
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)

      expect(run_plan('peadm::upgrade',
                       'primary_host'     => 'primary',
                       'version'          => '2023.3.0',
                       'r10k_known_hosts' => r10k_known_hosts,
                       'permit_unsafe_versions' => true)).to be_ok
    end

    it 'warns if upgrading to 2023.3+ from 2023.0- without r10k_known_hosts set' do
      # This is fairly horrible, but expect_out_message doesn't take a regex.
      expect_out_message.with_params(r10k_warning)
      expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)

      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })

      expect(run_plan('peadm::upgrade',
                       'primary_host'     => 'primary',
                       'version'          => '2023.3.0',
                       'permit_unsafe_versions' => true)).to be_ok
    end

    context 'upgrading from 2023.3+' do
      let(:installed_version) { '2023.3.0' }

      it 'does not warn if r10k_known_hosts is not set' do
        expect_out_message.with_params(r10k_warning).not_be_called
        expect_task('peadm::check_pe_master_rules').always_return(pe_rule_check)

        expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })

        expect(run_plan('peadm::upgrade',
                         'primary_host'     => 'primary',
                         'version'          => '2023.4.0',
                         'permit_unsafe_versions' => true)).to be_ok
      end
    end
  end
end
