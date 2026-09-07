require 'spec_helper'
require 'json'

describe 'peadm::subplans::install' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  let(:mockfile) { instance_double('Tempfile', path: '/mock', write: nil, flush: nil, close: nil, unlink: nil) }

  before(:each) do
    allow_any_task
    allow_any_plan
    allow_any_command
    allow_out_message

    allow_task('peadm::precheck').return_for_targets(
      'primary' => {
        'hostname' => 'primary',
        'platform' => 'el-7.11-x86_64',
      },
      'postgres1' => {
        'hostname' => 'postgres1',
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

  it 'installs 2023.8.11 with legacy compilers' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.11',
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
      'version' => '2023.8.11',
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
      'version' => '2023.8.11',
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

  # PE-46689: rbac-service can briefly 500/reject auth immediately after
  # the pe-puppetdb bounce just above this call, before its own dependents
  # have caught up -- the same class of transient-unavailability window
  # restore.pp's equivalent rbac_token call already retries around
  # (PE-44867). subplans::install had no equivalent retry.
  describe 'rbac_token retry (PE-46689)' do
    let(:params) do
      {
        'primary_host' => 'primary',
        'console_password' => 'puppetLabs123!',
        'version' => '2023.8.10',
      }
    end

    # error_with/always_return can't simulate a real failure result and then
    # a later success from the *same* stub (they set one fixed default for
    # every call) -- construct the Bolt::Result directly via a .return
    # block with a closure counter instead, so each successive call to
    # peadm::rbac_token can return a different result.
    def stub_rbac_token(fail_count:)
      attempts = 0
      expected_calls = [fail_count + 1, 5].min
      expect_task('peadm::rbac_token').with_targets('primary').be_called_times(expected_calls).return do |targets:, task:, params:| # rubocop:disable Lint/UnusedBlockArgument
        attempts += 1
        results = targets.map do |target|
          if attempts <= fail_count
            Bolt::Result.new(target, error: { 'msg' => 'User admin failed to login', 'kind' => 'puppetlabs.rbac/server-error' })
          else
            Bolt::Result.new(target, value: {})
          end
        end
        Bolt::ResultSet.new(results)
      end
    end

    # ctrl::sleep resolves Kernel#sleep as a private instance method (mixed
    # into every Object via the Kernel module), not the module_function
    # singleton `Kernel.sleep` -- stubbing the singleton doesn't intercept
    # it, so this needs any_instance_of like the file's other Ruby-internals
    # stubs above.
    # rubocop:disable RSpec/AnyInstance
    before(:each) do
      allow_any_instance_of(Puppet::Functions::Function).to receive(:sleep)
    end
    # rubocop:enable RSpec/AnyInstance

    it 'succeeds on the first attempt without retrying' do
      stub_rbac_token(fail_count: 0)

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    it 'retries and succeeds once rbac-service catches up' do
      stub_rbac_token(fail_count: 2)

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    it 'fails the install after exhausting all retry attempts' do
      stub_rbac_token(fail_count: 5)

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Failed to obtain RBAC token after 5 attempts})
    end
  end

  # PE-45431: on Large/XL/external-Postgres topologies the primary's installer
  # runs before $database_targets exist, so pe-installer-shim's own
  # migration (PE-45430) finds pe-ca unreachable and skips loudly -- peadm
  # must complete it once $database_targets have converged.
  describe 'ca_storage_import (PE-45431)' do
    let(:params) do
      {
        'primary_host' => 'primary',
        'console_password' => 'puppetLabs123!',
        'version' => '2023.8.11',
      }
    end
    # PE-46685: probes via `bolt plan show`, which resolves through the
    # installer Boltdir's full modulepath (site-modules, the enterprise
    # environment, then Boltdir/modules itself) -- the same resolution the
    # migration_command below relies on -- instead of statting one hardcoded
    # subdirectory of that modulepath that never actually contains
    # puppet_enterprise on a real install.
    let(:probe_command) do
      'BOLT_DISABLE_ANALYTICS=true BOLT_GEM=true /opt/puppetlabs/installer/bin/bolt ' \
        '--project /opt/puppetlabs/installer/share/Boltdir plan show puppet_enterprise::ca_storage_import'
    end
    # The exact literal command text the @("CMD"/L) heredoc in install.pp
    # produces: margin-trimmed backslash-continuation joins leave the
    # multi-space gaps below, and the heredoc always keeps its trailing
    # newline -- both confirmed by directly capturing the real command via
    # a temporary allow_any_command.return block, and consistent with the
    # same artifact already accepted verbatim in this repo's other heredoc-
    # backed command specs (e.g. restore_spec.rb, backup_spec.rb).
    let(:migration_command) do
      'BOLT_DISABLE_ANALYTICS=true BOLT_GEM=true /opt/puppetlabs/installer/bin/bolt   ' \
        '--project /opt/puppetlabs/installer/share/Boltdir plan run   ' \
        "puppet_enterprise::ca_storage_import targets=localhost\n"
    end

    # error_with/always_return can't simulate a real nonzero-exit command
    # result with custom stdout/stderr (BoltSpec's CommandStub#result_for
    # hardcodes exit_code to 0 either way) -- construct the Bolt::Result
    # directly via a .return block instead, matching how Bolt's own
    # Result.for_command builds a real command failure (stdout/stderr
    # preserved, 'puppetlabs.tasks/command-error' kind attached only when
    # exit_code != 0).
    def stub_probe_command_failure(stdout: '', stderr: '')
      expect_command(probe_command).with_targets('primary').return do |targets:, command:, params:| # rubocop:disable Lint/UnusedBlockArgument
        value = { 'stdout' => stdout, 'stderr' => stderr, 'exit_code' => 1 }
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.for_command(target, value, 'command', command, []) })
      end
    end

    it 'runs the migration on the primary when this PE version ships the plan' do
      expect_command(probe_command).with_targets('primary')
      expect_command(migration_command).with_targets('primary')

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    # Extra Large / external-Postgres: $database_targets is non-empty and
    # $primary_target is installed before it (see plans/subplans/install.pp,
    # peadm::pe_install on $primary_target then on $database_targets) --
    # this is the exact ordering that leaves pe-ca unreachable from the
    # shim's own migration (PE-45430), motivating this step in the first
    # place. Confirms the migration still targets the primary correctly
    # once a database target is in the mix.
    it 'runs the migration on the primary on a split (external-Postgres) topology' do
      xl_params = params.merge('primary_postgresql_host' => 'postgres')
      allow_task('peadm::precheck').return_for_targets(
        'primary' => { 'hostname' => 'primary', 'platform' => 'el-7.11-x86_64' },
        'postgres' => { 'hostname' => 'postgres', 'platform' => 'el-7.11-x86_64' },
      )

      expect_command(probe_command).with_targets('primary')
      expect_command(migration_command).with_targets('primary')

      expect(run_plan('peadm::subplans::install', xl_params)).to be_ok
    end

    it 'no-ops without running the migration when this PE version predates the feature' do
      stub_probe_command_failure(stdout: "Could not find a plan named 'puppet_enterprise::ca_storage_import'. " \
                                          "For a list of available plans, run 'bolt plan show'.\n")
      expect_command(migration_command).not_be_called

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    # `bolt plan show` prints its "not found" message to STDOUT, not stderr
    # (confirmed empirically) -- only that specific message on stdout may be
    # treated as "this PE version predates the feature." Anything else
    # (e.g. a Puppetfile/module-resolution error) is a real infrastructure
    # problem that must fail loudly, not silently skip a needed migration.
    it 'fails the install when the probe fails for a reason other than a missing plan' do
      stub_probe_command_failure(stderr: "Fatal Puppetfile error while resolving modules: connection refused\n")
      expect_command(migration_command).not_be_called

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{connection refused})
    end

    # A transport/connect failure must not be silently conflated with "this
    # PE version predates the feature" (both would otherwise present as a
    # non-ok probe result) -- it's a real infrastructure problem and must
    # fail the install loudly instead of skipping.
    it 'fails the install when the probe itself cannot be run (e.g. a transport failure)' do
      expect_command(probe_command).with_targets('primary')
                                   .error_with('msg' => 'Connection refused', 'kind' => 'puppetlabs.tasks/connect-error')
      expect_command(migration_command).not_be_called

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Connection refused})
    end

    # No _catch_errors on the migration run_command itself (unlike the
    # probe): a failure here raises Bolt's own uncaught PlanFailure and
    # halts the whole peadm::install run, matching the file's dominant
    # convention (pe_install, rbac_token, code_manager, etc. all fail the
    # same way). Bolt's own generated diagnostic names the exact command
    # and target that failed -- there is no additional message to surface
    # on top of that, per this plan's established style for uncaught
    # run_command calls.
    it 'fails the install when the migration itself fails' do
      expect_command(probe_command).with_targets('primary')
      expect_command(migration_command).with_targets('primary')
                                       .error_with('msg' => 'CA storage import failed', 'kind' => 'puppetlabs.tasks/command-error')

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{run_command.*failed on 1 target}m)
    end
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

  # PE-46576: on extra-large (split-database) installs, the primary's pe.conf
  # set puppetdb_database_host to the dedicated postgresql target but never
  # set the general database_host, so every non-PuppetDB service (rbac,
  # activity, classifier, etc.) fell back to a co-located Postgres on the
  # primary instead of the dedicated host -- leaving the default admin
  # account revoked and unable to authenticate.
  it 'sets database_host for the primary on extra-large (split-database) installs' do
    written_contents = []
    allow(mockfile).to receive(:write) { |content| written_contents << content }

    params = {
      'primary_host' => 'primary',
      'primary_postgresql_host' => 'postgres1',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
    }

    expect(run_plan('peadm::subplans::install', params)).to be_ok

    primary_pe_conf = written_contents.find { |content| content.include?('puppetdb_database_host') }
    expect(primary_pe_conf).to include('"puppet_enterprise::database_host": "postgres1"')
    expect(primary_pe_conf).to include('"puppet_enterprise::puppetdb_database_host": "postgres1"')
  end

  # PE-46576: pointing rbac/activity/classifier at the dedicated Postgres
  # host (fixed above) surfaced a sequencing bug -- that host isn't up yet
  # during the primary's own install pass, so those services' database
  # bootstrap silently failed and left the admin account revoked. Re-running
  # Puppet on the primary once the database host is up, before requesting an
  # rbac token, lets those services finish migrating and fix the account.
  it 'reconciles the primary with Puppet before requesting an rbac token on split-database installs' do
    params = {
      'primary_host' => 'primary',
      'primary_postgresql_host' => 'postgres1',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
    }

    allow_task('peadm::puppet_runonce')
    expect_task('peadm::puppet_runonce')
      .with_targets('primary')
      .with_params({ 'in_progress_timeout' => 600, '_catch_errors' => true })

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end
end
