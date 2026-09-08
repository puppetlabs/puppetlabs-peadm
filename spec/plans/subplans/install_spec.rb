require 'spec_helper'
require 'json'

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

  it 'installs 2023.8.10 with legacy compilers' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
      'legacy_compilers' => ['compiler1', 'compiler2'],
    }
    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  # PE-44595: when no dns_alt_names are supplied we must NOT emit a
  # `main:dns_alt_names=` flag, which would write a present-but-empty
  # `dns_alt_names = ` line into the agent's puppet.conf and later crash
  # `puppetserver ca generate` during a DR replica promotion.
  it 'omits the dns_alt_names install flag when none are supplied' do
    params = {
      'primary_host' => 'primary',
      'compiler_hosts' => ['compiler1'],
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
    }

    expect_task('peadm::agent_install')
      .with_params({ 'server'        => 'primary',
                     'install_flags' => [
                       '--puppet-service-ensure', 'stopped',
                       'main:certname=compiler1'
                     ] })

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  it 'sets the dns_alt_names install flag when alt names are supplied' do
    params = {
      'primary_host' => 'primary',
      'compiler_hosts' => ['compiler1'],
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
      'dns_alt_names' => ['puppet', 'alt.example.com'],
    }

    expect_task('peadm::agent_install')
      .with_params({ 'server'        => 'primary',
                     'install_flags' => [
                       '--puppet-service-ensure', 'stopped',
                       'main:certname=compiler1',
                       'main:dns_alt_names=puppet,alt.example.com'
                     ] })

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  # --- Precheck validation pair (install.pp ~179-192) ---------------------
  #
  # These two tests are a deliberate pair covering the two branches of the
  # precheck validation loop: a hostname mismatch (warn-and-continue) and a
  # platform mismatch (fail_plan). A mutation that swaps the warn/fail
  # behavior between the two `if` blocks (or that changes `fail_plan` to
  # `warning` or vice versa) will flip exactly one of these tests.
  describe 'precheck validation' do
    it 'fails the plan when a target reports a platform different from the primary (line ~189-191)' do
      allow_task('peadm::precheck').return_for_targets(
        'primary' => {
          'hostname' => 'primary',
          'platform' => 'el-7.11-x86_64',
        },
        'compiler1' => {
          'hostname' => 'compiler1',
          'platform' => 'el-8.4-x86_64',
        },
      )

      params = {
        'primary_host' => 'primary',
        'compiler_hosts' => ['compiler1'],
        'console_password' => 'puppetLabs123!',
        'version' => '2023.8.10',
      }

      result = run_plan('peadm::subplans::install', params)

      # A platform mismatch must fail the whole install; a mutation that
      # turns this fail_plan into a no-op or a warning would leave this
      # plan reporting success, which this catches.
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Platform mismatch})
      expect(result.value.msg).to match(%r{compiler1})
      expect(result.value.msg).to match(%r{el-8\.4-x86_64})
      expect(result.value.msg).to match(%r{el-7\.11-x86_64})
    end

    it 'warns but does not fail the plan when a target hostname does not match its target name, as long as platforms agree (line ~181-188)' do
      allow_task('peadm::precheck').return_for_targets(
        'primary' => {
          'hostname' => 'primary',
          'platform' => 'el-7.11-x86_64',
        },
        'compiler1' => {
          'hostname' => 'not-compiler1',
          'platform' => 'el-7.11-x86_64',
        },
      )

      logged_warnings = []
      # `warning()` in Puppet plan code logs via Puppet::Util::Log.create,
      # not via the bolt out::message channel, so it must be intercepted
      # here rather than with expect_out_message/allow_out_message.
      allow(Puppet::Util::Log).to receive(:create).and_wrap_original do |original, log_hash|
        logged_warnings << log_hash if log_hash.is_a?(Hash) && log_hash[:level] == :warning
        original.call(log_hash)
      end

      params = {
        'primary_host' => 'primary',
        'compiler_hosts' => ['compiler1'],
        'console_password' => 'puppetLabs123!',
        'version' => '2023.8.10',
      }

      result = run_plan('peadm::subplans::install', params)

      # A hostname mismatch alone must NOT fail the plan. A mutation that
      # turns this warning into a fail_plan would flip this to `not_to be_ok`,
      # catching a swap between the two branches.
      expect(result).to be_ok

      mismatch_warning = logged_warnings.find { |w| w[:message].to_s.include?('Target name / hostname mismatch') }
      expect(mismatch_warning).not_to be_nil
      expect(mismatch_warning[:message]).to match(%r{target compiler1 reports not-compiler1})
    end
  end

  # --- DR compiler A/B availability-group split (install.pp ~126-138) -----
  #
  # No existing test combines replica_host with multiple compiler_hosts, so
  # nothing exercises the `$index % 2` split that divides compilers between
  # PuppetDB availability groups A and B in a disaster-recovery
  # architecture. A mutation that flips `== 0` to `!= 0` (or otherwise swaps
  # which half goes to A vs B) is only caught by asserting the exact
  # membership of each group, which is what this test does by inspecting the
  # extension_requests/targets passed to
  # peadm::util::insert_csr_extension_requests.
  it 'splits compiler_hosts into availability groups A (even index) and B (odd index) for a DR architecture' do
    allow_task('peadm::precheck').return_for_targets(
      'primary' => { 'hostname' => 'primary', 'platform' => 'el-7.11-x86_64' },
      'replica' => { 'hostname' => 'replica', 'platform' => 'el-7.11-x86_64' },
      'compiler1' => { 'hostname' => 'compiler1', 'platform' => 'el-7.11-x86_64' },
      'compiler2' => { 'hostname' => 'compiler2', 'platform' => 'el-7.11-x86_64' },
      'compiler3' => { 'hostname' => 'compiler3', 'platform' => 'el-7.11-x86_64' },
      'compiler4' => { 'hostname' => 'compiler4', 'platform' => 'el-7.11-x86_64' },
    )

    csr_calls = []
    allow_plan('peadm::util::insert_csr_extension_requests').return do |params:, **|
      csr_calls << {
        targets: Array(params['targets']).map(&:name),
        extension_requests: params['extension_requests'],
      }
      Bolt::PlanResult.new({}, 'success')
    end

    params = {
      'primary_host' => 'primary',
      'replica_host' => 'replica',
      'compiler_hosts' => ['compiler1', 'compiler2', 'compiler3', 'compiler4'],
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
    }

    expect(run_plan('peadm::subplans::install', params)).to be_ok

    # peadm::oid('pp_auth_role') and peadm::oid('peadm_availability_group')
    pp_auth_role_oid = '1.3.6.1.4.1.34380.1.3.13'
    avail_group_oid = '1.3.6.1.4.1.34380.1.1.9813'

    compiler_calls = csr_calls.select { |c| c[:extension_requests][pp_auth_role_oid] == 'pe_compiler' }

    group_a = compiler_calls.find { |c| c[:extension_requests][avail_group_oid] == 'A' }
    group_b = compiler_calls.find { |c| c[:extension_requests][avail_group_oid] == 'B' }

    expect(group_a).not_to be_nil
    expect(group_b).not_to be_nil
    expect(group_a[:targets].sort).to eq(['compiler1', 'compiler3'])
    expect(group_b[:targets].sort).to eq(['compiler2', 'compiler4'])
  end

  # --- code_manager_auto_configure implicit-true branch (install.pp ~161-169) ---
  #
  # Only the "r10k_remote + explicit flag=true" branch was previously
  # tested. This exercises the separate "implied true because replica_host
  # is set" elsif branch (no r10k_remote, no compilers). A mutation that
  # merges/collapses this elsif into the r10k_remote branch (e.g. changing
  # `elsif $replica_host` to `elsif $r10k_remote and $replica_host`) would
  # leave code_manager_auto_configure unset/false here, which this catches
  # by asserting on the generated primary pe.conf content.
  it 'implicitly enables code_manager_auto_configure when only replica_host is set (no r10k_remote, no compilers)' do
    allow_task('peadm::precheck').return_for_targets(
      'primary' => { 'hostname' => 'primary', 'platform' => 'el-7.11-x86_64' },
      'replica' => { 'hostname' => 'replica', 'platform' => 'el-7.11-x86_64' },
    )

    uploaded_contents = []
    # Re-stub the Tempfile double set up in the top-level before(:each) so
    # that writes to it (the pe.conf content peadm::file_content_upload
    # writes before uploading) are captured for inspection.
    allow(Tempfile).to receive(:new).with('peadm') do
      file = instance_double('Tempfile', path: '/mock', flush: nil, close: nil, unlink: nil)
      allow(file).to receive(:write) { |content| uploaded_contents << content }
      file
    end

    params = {
      'primary_host' => 'primary',
      'replica_host' => 'replica',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
    }

    expect(run_plan('peadm::subplans::install', params)).to be_ok

    primary_pe_conf = uploaded_contents
                      .map { |c| JSON.parse(c) }
                      .find { |c| c.key?('puppet_enterprise::profile::master::code_manager_auto_configure') }

    expect(primary_pe_conf).not_to be_nil
    expect(primary_pe_conf['puppet_enterprise::profile::master::code_manager_auto_configure']).to eq(true)
  end
end
