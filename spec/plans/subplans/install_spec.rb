require 'spec_helper'

describe 'peadm::subplans::install' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

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
    let(:plan_file) { '/opt/puppetlabs/installer/share/Boltdir/modules/puppet_enterprise/plans/ca_storage_import.pp' }
    let(:probe_command) { "stat '#{plan_file}'" }
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
    # result with custom stderr (BoltSpec's CommandStub#result_for hardcodes
    # exit_code to 0 either way) -- construct the Bolt::Result directly via
    # a .return block instead, matching how Bolt's own Result.for_command
    # builds a real command failure (stdout/stderr preserved, 'puppetlabs.
    # tasks/command-error' kind attached only when exit_code != 0).
    def stub_probe_command_failure(stderr:)
      expect_command(probe_command).with_targets('primary').return do |targets:, command:, params:| # rubocop:disable Lint/UnusedBlockArgument
        value = { 'stdout' => '', 'stderr' => stderr, 'exit_code' => 1 }
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
      stub_probe_command_failure(stderr: "stat: cannot stat '#{plan_file}': No such file or directory")
      expect_command(migration_command).not_be_called

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    # The whole reason this probes with `stat` instead of `test -f`: a real
    # permissions problem on the installer's own Boltdir exits non-zero
    # identically to a genuinely missing file, but stat's stderr text is
    # different for the two cases, and only "No such file or directory" may
    # be treated as "this PE version predates the feature." Anything else
    # (e.g. "Permission denied") is a real infrastructure problem that must
    # fail loudly, not silently skip a needed migration.
    it 'fails the install when the probe fails for a reason other than a missing file' do
      stub_probe_command_failure(stderr: "stat: cannot stat '#{plan_file}': Permission denied")
      expect_command(migration_command).not_be_called

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Permission denied})
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
end
