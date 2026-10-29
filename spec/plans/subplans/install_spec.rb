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

  it 'fails when the post-install wait_until_service_ready times out' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2019.8.12',
    }

    expect_task('peadm::wait_until_service_ready')
      .with_targets('primary')
      .error_with('msg' => 'Timed out waiting for service', 'kind' => 'puppetlabs.tasks/task-error')

    result = run_plan('peadm::subplans::install', params)
    expect(result).not_to be_ok
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
  #
  # PE-46917: the original 5-attempt/15s margin (added for PE-46689) still
  # wasn't enough -- nightly CI continued exhausting all 5 attempts after
  # the pe-puppetdb bounce. Live reproduction on a dedicated test VM (idle,
  # under induced CPU load, and under induced CPU+disk-IO load) never
  # reproduced the underlying race, so there's no measured number to widen
  # to; this widens the budget generously (10 attempts/20s, exactly 3x the
  # total window) as a defensive margin rather than a precisely-measured one.
  describe 'rbac_token retry (PE-46689, widened per PE-46917)' do
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
    # Each failing attempt gets its own distinct error text (embedding the
    # attempt number) rather than one fixed string repeated for every
    # failure -- otherwise an off-by-one bug that logs a stale/wrong
    # attempt's error would produce byte-identical output to correct
    # behavior and no assertion here could tell the difference. Callers that
    # need specific error content (e.g. to test sanitization) can override it
    # via error_msg: instead of duplicating this closure-counter plumbing.
    def stub_rbac_token(fail_count:, error_msg: nil)
      attempts = 0
      expected_calls = [fail_count + 1, 10].min
      expect_task('peadm::rbac_token').with_targets('primary').be_called_times(expected_calls).return do |targets:, task:, params:| # rubocop:disable Lint/UnusedBlockArgument
        attempts += 1
        results = targets.map do |target|
          if attempts <= fail_count
            Bolt::Result.new(target, error: { 'msg' => error_msg || "User admin failed to login (task-attempt #{attempts})", 'kind' => 'puppetlabs.rbac/server-error' })
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
      allow_any_instance_of(Puppet::Functions::Function).to receive(:sleep).with(20)
    end
    # rubocop:enable RSpec/AnyInstance

    it 'succeeds on the first attempt without retrying' do
      stub_rbac_token(fail_count: 0)

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    it 'retries and succeeds once rbac-service catches up' do
      stub_rbac_token(fail_count: 2)

      expect_out_message.with_params('rbac_token not ready (User admin failed to login (task-attempt 1)); retrying (attempt 2) after 20s...')
      expect_out_message.with_params('rbac_token not ready (User admin failed to login (task-attempt 2)); retrying (attempt 3) after 20s...')

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    it 'retries past the old 5-attempt ceiling and succeeds within the widened 10-attempt budget' do
      stub_rbac_token(fail_count: 7)

      # Assert on the two retry messages that only exist because of this
      # widening (attempts 7 and 8 are past the old 5-attempt ceiling) --
      # without these, a message-threading bug reachable only past attempt 5
      # would be invisible even though this test is specifically meant to
      # validate that territory.
      expect_out_message.with_params('rbac_token not ready (User admin failed to login (task-attempt 6)); retrying (attempt 7) after 20s...')
      expect_out_message.with_params('rbac_token not ready (User admin failed to login (task-attempt 7)); retrying (attempt 8) after 20s...')

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    # The task's error message can carry external content (a connection error's
    # text, or Bolt's "stderr contained: ..." output), and PE-46689's own retry
    # loop already carries it into fail_plan on final exhaustion --
    # surfacing it on every retry too widens where it can end up, so it must be
    # sanitized rather than logged verbatim: newlines could forge/obscure
    # adjacent CI log lines, and an unexpectedly large payload shouldn't get
    # echoed in full into every retry's log line.
    it 'sanitizes newlines and caps the length of the prior error before logging it on retry' do
      unsanitized_error = "line one\nline two\r\nline three#{'x' * 300}"
      stub_rbac_token(fail_count: 1, error_msg: unsanitized_error)

      sanitized_and_capped = ('line one line two line three' + ('x' * 300))[0, 200]
      expect_out_message.with_params("rbac_token not ready (#{sanitized_and_capped}); retrying (attempt 2) after 20s...")

      expect(run_plan('peadm::subplans::install', params)).to be_ok
    end

    # PE-47009: a permanent failure (wrong console_password, malformed
    # request) is tagged with the peadm/rbac-auth-failure kind by the task;
    # retrying it for the full budget only delays reporting the misconfiguration.
    it 'fails fast without retrying on a permanent rbac auth failure' do
      expect_task('peadm::rbac_token').with_targets('primary').be_called_times(1)
                                      .error_with({ 'msg' => 'Error requesting token, {"msg":"bad password"}', 'kind' => 'peadm/rbac-auth-failure' })

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to eq('Failed to obtain RBAC token, permanent failure (not retrying): Error requesting token, {"msg":"bad password"}')
    end

    it 'stops retrying as soon as a permanent failure follows transient ones' do
      attempts = 0
      expect_task('peadm::rbac_token').with_targets('primary').be_called_times(3).return do |targets:, **|
        attempts += 1
        kind = (attempts < 3) ? 'puppetlabs.tasks/task-error' : 'peadm/rbac-auth-failure'
        Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, error: { 'msg' => "attempt #{attempts}", 'kind' => kind }) })
      end

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to eq('Failed to obtain RBAC token, permanent failure (not retrying): attempt 3')
    end

    # A permanent failure on the very last attempt ends the loop by reduce
    # exhaustion rather than the short-circuit, and must still be reported as
    # permanent.
    it 'reports a permanent failure on the final attempt as permanent' do
      attempts = 0
      expect_task('peadm::rbac_token').with_targets('primary').be_called_times(10).return do |targets:, **|
        attempts += 1
        kind = (attempts < 10) ? 'puppetlabs.tasks/task-error' : 'peadm/rbac-auth-failure'
        Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, error: { 'msg' => "attempt #{attempts}", 'kind' => kind }) })
      end

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to eq('Failed to obtain RBAC token, permanent failure (not retrying): attempt 10')
    end

    it 'fails the install after exhausting all retry attempts' do
      stub_rbac_token(fail_count: 10)

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      # Asserts the full message, including the 10th (final) attempt's own
      # error text -- not just the attempt-count prefix -- so a bug that
      # reports a stale or wrong attempt's error in the terminal failure
      # message would be caught here too.
      expect(result.value.msg).to eq('Failed to obtain RBAC token after 10 attempts: User admin failed to login (task-attempt 10)')
    end

    # Bolt's JSON outputter (--format json, realistic for CI harnesses needing
    # machine-parseable output) calls JSON.generate on plan failure messages,
    # which raises JSON::GeneratorError on invalid UTF-8. The per-retry message
    # is already sanitized (see above); this proves the terminal fail_plan
    # message -- the one exhaustion actually surfaces -- goes through the same
    # sanitizer, so a malformed final error can't crash the failure report
    # itself in exactly the CI scenario this ticket exists to fix.
    it 'sanitizes the final error text in the exhaustion message too' do
      unsanitized_error = "line one\nline two#{'x' * 300}"
      stub_rbac_token(fail_count: 10, error_msg: unsanitized_error)

      result = run_plan('peadm::subplans::install', params)
      expect(result).not_to be_ok
      sanitized_and_capped = ('line one line two' + ('x' * 300))[0, 200]
      expect(result.value.msg).to eq("Failed to obtain RBAC token after 10 attempts: #{sanitized_and_capped}")
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

  # PE-47384: on extra-large (split-database) installs, only PuppetDB's
  # database belongs on the dedicated postgresql host. Setting the general
  # database_host (as PE-46576 did) also moves the console databases off the
  # primary, but PE's replica profile always replicates those from the
  # primary node itself, so a DR replica syncs empty databases and its
  # console services never start.
  it 'sets only puppetdb_database_host, not database_host, for the primary on extra-large installs' do
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
    expect(primary_pe_conf).to include('"puppet_enterprise::puppetdb_database_host": "postgres1"')
    expect(primary_pe_conf).not_to include('"puppet_enterprise::database_host"')
  end

  # PE-46576: on split-database installs, the primary's own install pass
  # runs before the dedicated Postgres host is up. Every one-time bootstrap
  # step in that pass which depends on a database-backed service -- rbac's
  # admin account activation, classifier's default node groups, and
  # potentially others -- fails silently when it calls that service's local
  # API, because the service can't reach its now-remote database yet. Those
  # steps only exist in the installer's one-shot catalog apply, so nothing
  # later (including a normal Puppet run) ever retries them. Re-run the
  # installer once the database host is confirmed up, before requesting an
  # rbac token, so it can finish what it couldn't the first time.
  it 'reinstalls the primary before requesting an rbac token on split-database installs' do
    params = {
      'primary_host' => 'primary',
      'primary_postgresql_host' => 'postgres1',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
    }

    expect_task('peadm::pe_reinstall')
      .with_targets('primary')
      .with_params({
                     'installer_dir' => '/tmp/puppet-enterprise-2023.8.10-el-7.11-x86_64',
                     'peconf'        => '/tmp/pe.conf',
                   })

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  it 'does not reinstall the primary on standard (non-split-database) installs' do
    params = {
      'primary_host' => 'primary',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
    }

    expect_task('peadm::pe_reinstall').not_be_called

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  # See install.pp's $pe_installer_dir comment for why internal dev/RC
  # builds ship as a plain .tar (only public released builds use .tar.gz).
  # Before this fix, $pe_installer_dir's regsubst only stripped a literal
  # '.tar.gz' suffix, so a bare '.tar' source (set via pe_installer_source
  # below) left the extension attached: 'installer_dir' came out as
  # '/tmp/puppet-enterprise-....tar' instead of the real extracted directory
  # ('/tmp/puppet-enterprise-...', no extension). peadm::pe_reinstall then
  # failed every time with "Puppet Enterprise installer not found", blocking
  # every extra-large install tested against an internal dev build.
  it 'reinstalls the primary using the correctly-stripped installer_dir for a bare .tar source' do
    params = {
      'primary_host' => 'primary',
      'primary_postgresql_host' => 'postgres1',
      'console_password' => 'puppetLabs123!',
      'version' => '2023.8.10',
      'pe_installer_source' => 'https://artifactory.example.com/main/ci-ready/puppet-enterprise-2023.8.10-el-7.11-x86_64.tar',
    }

    expect_task('peadm::pe_reinstall')
      .with_targets('primary')
      .with_params({
                     'installer_dir' => '/tmp/puppet-enterprise-2023.8.10-el-7.11-x86_64',
                     'peconf'        => '/tmp/pe.conf',
                   })

    expect(run_plan('peadm::subplans::install', params)).to be_ok
  end

  # PE-47523: Bolt writes every task's arguments to bolt-debug.log and masks
  # only the parameters a task's metadata flags "sensitive", so the calls
  # that carry secrets must go through those parameters, which BoltSpec then
  # sees wrapped as Sensitive. The plans take console_password as a plain
  # String (peadm::migrate passes one); the wrapping comes from the task
  # metadata.
  describe 'secrets in task arguments and on disk (PE-47523)' do
    let(:install_params) do
      {
        'primary_host'             => 'primary',
        'console_password'         => 'puppetLabs123!',
        'version'                  => '2023.8.10',
        'r10k_remote'              => 'git@github.com:puppetlabs/nothing',
        'r10k_private_key_content' => '-----BEGIN r10k-key-canary',
        'license_key_content'      => 'license-canary',
      }
    end
    # A raw / inside the query, as in an AWS credential scope
    let(:signed_source) do
      'https://bucket.s3.amazonaws.com/released/puppet-enterprise-2023.8.10-el-7.11-x86_64.tar.gz' \
        '?X-Amz-Credential=AKIA-canary/20261029/us-east-1/s3/aws4_request&X-Amz-Signature=signature-canary'
    end
    let(:tarball) { '/tmp/puppet-enterprise-2023.8.10-el-7.11-x86_64.tar.gz' }

    def command_results(targets, command, exit_code: 0, stderr: '')
      Bolt::ResultSet.new(targets.map do |target|
        Bolt::Result.for_command(target, { 'stdout' => '', 'stderr' => stderr, 'exit_code' => exit_code }, 'command', command, [])
      end)
    end

    # Records every task, command, plan and upload, in order, as
    # "<task or command>@<target>", "<plan>" or "upload <destination>@<target>",
    # and returns the log.
    def record_calls
      call_log = []
      allow_any_task.return do |targets:, task:, **|
        targets.each { |target| call_log << "#{task}@#{target.name}" }
        ok_results(targets)
      end
      allow_any_command.return do |targets:, command:, **|
        targets.each { |target| call_log << "#{command}@#{target.name}" }
        command_results(targets, command)
      end
      allow_any_plan.return do |plan:, **|
        call_log << plan.closure_name
        Bolt::PlanResult.new({}, 'success')
      end
      allow_upload('/mock').return do |targets:, destination:, **|
        targets.each { |target| call_log << "upload #{destination}@#{target.name}" }
        Bolt::ResultSet.new(targets.map { |target| Bolt::Result.for_upload(target, '/mock', destination) })
      end
      call_log
    end

    it 'passes the console password to rbac_token as Sensitive' do
      expect_task('peadm::rbac_token').with_targets('primary').return do |targets:, params:, **|
        expect(params['password']).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
        expect(params['password'].unwrap).to eq('puppetLabs123!')
        ok_results(targets)
      end

      expect(run_plan('peadm::subplans::install', install_params)).to be_ok
    end

    it 'writes pe.conf, the r10k key and the license to the primary as Sensitive content' do
      primary_contents = {}
      allow_task('peadm::mkdir_p_file').return do |targets:, params:, **|
        primary_contents[params['path']] = params['content'] if targets.map(&:name) == ['primary']
        ok_results(targets)
      end

      expect(run_plan('peadm::subplans::install', install_params)).to be_ok

      {
        '/etc/puppetlabs/enterprise/conf.d/pe.conf'            => '"console_admin_password": "puppetLabs123!"',
        '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa' => 'r10k-key-canary',
        '/etc/puppetlabs/license.key'                          => 'license-canary',
      }.each do |path, secret|
        content = primary_contents[path]
        expect(content).not_to be_nil, "no mkdir_p_file call wrote #{path} on the primary"
        expect(content).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive), "#{path} content is not Sensitive"
        expect(content.unwrap).to include(secret)
      end
    end

    # Renders every task call and command the way Bolt logs them, so a secret
    # passed through any unflagged parameter or command line fails here, not
    # only in the acceptance canary check.
    { 'standard' => {}, 'extra-large' => { 'primary_postgresql_host' => 'postgres1' } }.each do |architecture, extra|
      it "logs no secret in any task argument or command (#{architecture})" do
        logged = []
        allow_any_task.return do |targets:, task:, params:|
          logged << "Running task #{task} with '#{params.reject { |key, _| key.start_with?('_') }.to_json}'"
          ok_results(targets)
        end
        allow_any_command.return do |targets:, command:, **|
          logged << "Running command '#{command}'"
          command_results(targets, command)
        end

        expect(run_plan('peadm::subplans::install', install_params.merge(extra))).to be_ok

        # Positive control: the sweep saw rbac_token's masked password.
        expect(logged).to include(a_string_including(%q(Running task peadm::rbac_token with '{"password":"Sensitive [value redacted]")))
        leaks = logged.grep(%r{puppetLabs123!|r10k-key-canary|license-canary})
        expect(leaks).to be_empty, "secrets in logged task arguments or commands:\n#{leaks.join("\n")}"
      end
    end

    # A pre-signed URL carries its credentials in the query string, so the
    # tarball is named from the URL's path alone. The name becomes the tarball
    # path (a task argument, and part of download.sh's output) and the
    # installer directory.
    it 'keeps a pre-signed URL query string out of the tarball path and installer directory' do
      expect_plan('peadm::util::retrieve_and_upload').return do |params:, **|
        expect(params['source']).to eq(signed_source)
        expect(params['local_path']).to eq(tarball)
        expect(params['upload_path']).to eq(tarball)
        Bolt::PlanResult.new({}, 'success')
      end
      expect_task('peadm::pe_install').with_targets('primary').with_params(
        'tarball'               => tarball,
        'peconf'                => '/tmp/pe.conf',
        'puppet_service_ensure' => 'stopped',
        'install_extra_large'   => true,
      )
      expect_task('peadm::pe_install').with_targets('postgres1').with_params(
        'tarball'               => tarball,
        'peconf'                => '/tmp/pe.conf',
        'puppet_service_ensure' => 'stopped',
      )
      expect_task('peadm::pe_reinstall').with_targets('primary').with_params(
        'installer_dir' => '/tmp/puppet-enterprise-2023.8.10-el-7.11-x86_64',
        'peconf'        => '/tmp/pe.conf',
      )

      expect(run_plan('peadm::subplans::install',
                      install_params.merge('primary_postgresql_host' => 'postgres1', 'pe_installer_source' => signed_source))).to be_ok
    end

    # Where the user info ends can't be told when the password holds a raw /
    # and there's no path: what's left of it used to become the file name
    it 'keeps user info out of the tarball path even when the password has a raw /' do
      expect_plan('peadm::util::retrieve_and_upload').return do |params:, **|
        expect(params['local_path']).to eq(tarball)
        expect(params['upload_path']).to eq(tarball)
        Bolt::PlanResult.new({}, 'success')
      end

      source = 'https://ci:Pa55/word-canary@artifacts.example.com'
      expect(run_plan('peadm::subplans::install', install_params.merge('pe_installer_source' => source))).to be_ok
    end

    # Every version's download.cgi?...&ver= link has the same file name, so a
    # tarball of another version, cached on the Bolt host, would be installed.
    it 'names the tarball after version and platform when the URL has no tarball file name' do
      expect_plan('peadm::util::retrieve_and_upload').return do |params:, **|
        expect(params['local_path']).to eq(tarball)
        expect(params['upload_path']).to eq(tarball)
        Bolt::PlanResult.new({}, 'success')
      end

      source = 'https://pm.puppet.com/cgi-bin/download.cgi?dist=el&rel=7&arch=x86_64&ver=2023.8.10'
      expect(run_plan('peadm::subplans::install', install_params.merge('pe_installer_source' => source))).to be_ok
    end

    # Artifactory dev/RC builds ship as a plain .tar
    it "keeps the URL's own name for a plain .tar source" do
      expect_plan('peadm::util::retrieve_and_upload').return do |params:, **|
        expect(params['local_path']).to eq('/tmp/puppet-enterprise-2026.0.0-el-7.11-x86_64.tar')
        Bolt::PlanResult.new({}, 'success')
      end
      expect_task('peadm::pe_install').with_targets('primary').with_params(
        'tarball'               => '/tmp/puppet-enterprise-2026.0.0-el-7.11-x86_64.tar',
        'peconf'                => '/tmp/pe.conf',
        'puppet_service_ensure' => 'stopped',
        'install_extra_large'   => false,
      )

      source = 'https://artifacts.example.com/ci/puppet-enterprise-2026.0.0-el-7.11-x86_64.tar'
      expect(run_plan('peadm::subplans::install', install_params.merge('pe_installer_source' => source))).to be_ok
    end

    # The name comes from the path, not from a tarball-looking name in the query
    it 'ignores a tarball-looking name in the query string' do
      expect_plan('peadm::util::retrieve_and_upload').return do |params:, **|
        expect(params['local_path']).to eq(tarball)
        Bolt::PlanResult.new({}, 'success')
      end

      source = 'https://artifacts.example.com/download?file=pe-other-1.0.0-el-7-x86_64.tar.gz'
      expect(run_plan('peadm::subplans::install', install_params.merge('pe_installer_source' => source))).to be_ok
    end

    it 'downloads a pre-signed URL directly through the masked source parameter' do
      expect_task('peadm::download').with_targets('primary').return do |targets:, params:, **|
        expect(params['source']).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
        expect(params['source'].unwrap).to eq(signed_source)
        expect(params['path']).to eq(tarball)
        ok_results(targets)
      end

      expect(run_plan('peadm::subplans::install',
                      install_params.merge('download_mode' => 'direct', 'pe_installer_source' => signed_source))).to be_ok
    end

    # Only the installer runs read the bootstrap pe.conf, and the primary's
    # copy holds the console password, so it's on the nodes only while they
    # run: uploaded after the download and CSR steps, and removed right after
    # the installer runs, before the steps a failed install most often stops at.
    it 'uploads /tmp/pe.conf just before the installer runs and removes it right after the installer runs' do
      call_log = record_calls
      allow_task('peadm::precheck').return_for_targets(
        'primary'      => { 'hostname' => 'primary', 'platform' => 'el-7.11-x86_64' },
        'replica'      => { 'hostname' => 'replica', 'platform' => 'el-7.11-x86_64' },
        'postgres1'    => { 'hostname' => 'postgres1', 'platform' => 'el-7.11-x86_64' },
        'postgres2'    => { 'hostname' => 'postgres2', 'platform' => 'el-7.11-x86_64' },
      )

      params = install_params.merge('replica_host' => 'replica', 'primary_postgresql_host' => 'postgres1', 'replica_postgresql_host' => 'postgres2')
      expect(run_plan('peadm::subplans::install', params)).to be_ok

      first_reader = call_log.index { |call| call.start_with?('peadm::pe_install@') }
      last_reader = call_log.rindex { |call| call.start_with?('peadm::pe_install@', 'peadm::pe_reinstall@') }
      ['primary', 'postgres1', 'postgres2'].each do |node|
        uploaded = call_log.index("upload /tmp/pe.conf@#{node}")
        removed = call_log.index("rm -f /tmp/pe.conf@#{node}")
        expect(uploaded).not_to be_nil, "/tmp/pe.conf was not uploaded to #{node}"
        expect(uploaded).to be > call_log.index('peadm::util::retrieve_and_upload')
        expect(uploaded).to be > call_log.rindex('peadm::util::insert_csr_extension_requests')
        expect(uploaded).to be < first_reader
        expect(removed).not_to be_nil, "/tmp/pe.conf was not removed on #{node}"
        expect(removed).to be > last_reader
        expect(removed).to be < call_log.index('peadm::rbac_token@primary')
      end
    end

    # The primary's upload can have worked when another node's didn't, and the
    # file must still be removed then. BoltSpec's executor hands back the
    # failed results of a parallelize block instead of raising the
    # ParallelFailure real Bolt raises, so that failure can't be played out
    # here. This deliberate source-order guard checks that the upload comes
    # after the catch_errors line, and so inside its block, and before the
    # installers and the cleanup.
    it 'uploads the bootstrap pe.conf after the catch_errors line and before the cleanup' do
      source = File.read(File.expand_path('../../../plans/subplans/install.pp', __dir__))
      block_start = source.index('$installer_error = catch_errors()')
      upload = source.index('peadm::file_content_upload($pe_conf, $bootstrap_pe_conf, $target)')
      installer = source.index("run_task('peadm::pe_install'")
      cleanup = source.index('rm -f ${bootstrap_pe_conf}')

      expect([block_start, upload, installer, cleanup]).to all(be_a(Integer))
      expect(block_start).to be < upload
      expect(upload).to be < installer
      expect(installer).to be < cleanup
    end

    it 'uploads no /tmp/pe.conf when the download fails' do
      call_log = record_calls
      expect_plan('peadm::util::retrieve_and_upload').error_with('kind' => 'peadm/download-error', 'msg' => 'Download failed')

      result = run_plan('peadm::subplans::install', install_params)

      expect(result).not_to be_ok
      expect(result.value.kind).to eq('peadm/download-error')
      expect(call_log.grep(%r{\Aupload /tmp/pe\.conf@})).to be_empty
    end

    # PE rejects a weak console_password late in the installer run, and the
    # file with the password must not stay behind then.
    context 'when an installer run fails' do
      let(:call_log) { record_calls }

      before(:each) do
        log = call_log
        allow_task('peadm::pe_install').return do |targets:, **|
          targets.each { |target| log << "peadm::pe_install@#{target.name}" }
          # shaped like a real failed task: what it printed is under _output
          Bolt::ResultSet.new(targets.map { |target| Bolt::Result.for_task(target, "Installer: password is too weak\n", '', 1, 'peadm::pe_install', []) })
        end
      end

      it 'removes /tmp/pe.conf, prints the failed node and its output, and fails with the installer error' do
        expect_out_message.with_params("Failed on primary: The task failed with exit code 1\nInstaller: password is too weak\n")

        result = run_plan('peadm::subplans::install', install_params)

        expect(result).not_to be_ok
        expect(result.value.msg).to include('peadm::pe_install')
        expect(call_log).to include('rm -f /tmp/pe.conf@primary')
        expect(call_log.index('rm -f /tmp/pe.conf@primary')).to be > call_log.index('peadm::pe_install@primary')
        expect(call_log).not_to include('peadm::rbac_token@primary')
      end

      # The block also runs commands (restarting PuppetDB), whose results have
      # stdout and stderr where a task's has _output
      it 'prints the output of a failed command too' do
        expect_out_message.with_params("Failed on primary: The command failed with exit code 5\ncommand-err-canary\n")
        allow_command('systemctl start pe-puppetdb').return do |targets:, command:, **|
          command_results(targets, command, exit_code: 5, stderr: "command-err-canary\n")
        end
        allow_task('peadm::pe_install').always_return({})

        result = run_plan('peadm::subplans::install', install_params)

        expect(result).not_to be_ok
        expect(result.value.msg).to include('systemctl start pe-puppetdb')
      end

      # rm's stderr can be in any encoding (a localized message, say); it must
      # not make the warning raise and replace the installer's error
      it 'still fails with the installer error when rm fails with stderr that is not UTF-8' do
        expect_command('rm -f /tmp/pe.conf').with_targets(['primary']).return do |targets:, command:, **|
          # tagged UTF-8 but not valid, which is what makes a regex on it raise
          command_results(targets, command, exit_code: 1, stderr: "rm: Op\xE9ration non permise\n".dup.force_encoding('UTF-8'))
        end
        expect_out_message.with_params(
          'WARNING: /tmp/pe.conf may still be on primary (rm: Op?ration non permise). ' \
          'Delete it by hand; on the primary it holds the console password.',
        )

        result = run_plan('peadm::subplans::install', install_params)

        expect(result).not_to be_ok
        expect(result.value.msg).to include('peadm::pe_install')
      end

      # The warning falls back to the error's message when rm printed nothing
      it 'warns with the error message when rm fails without stderr' do
        expect_command('rm -f /tmp/pe.conf').with_targets(['primary']).return do |targets:, command:, **|
          command_results(targets, command, exit_code: 1)
        end
        expect_out_message.with_params(
          'WARNING: /tmp/pe.conf may still be on primary (The command failed with exit code 1). ' \
          'Delete it by hand; on the primary it holds the console password.',
        )

        result = run_plan('peadm::subplans::install', install_params)

        expect(result).not_to be_ok
        expect(result.value.msg).to include('peadm::pe_install')
      end

      # A node rm can't reach has no stderr at all
      it 'warns with the error message when the node cannot be reached' do
        expect_command('rm -f /tmp/pe.conf').with_targets(['primary'])
                                            .error_with('kind' => 'puppetlabs.tasks/command-error', 'msg' => 'Connection refused')
        expect_out_message.with_params(
          'WARNING: /tmp/pe.conf may still be on primary (Connection refused). ' \
          'Delete it by hand; on the primary it holds the console password.',
        )

        result = run_plan('peadm::subplans::install', install_params)

        expect(result).not_to be_ok
        expect(result.value.msg).to include('peadm::pe_install')
      end

      # The removal's own failure is a warning and doesn't replace the error
      it "still fails with the installer error when /tmp/pe.conf can't be removed either" do
        expect_command('rm -f /tmp/pe.conf').with_targets(['primary']).return do |targets:, command:, **|
          command_results(targets, command, exit_code: 1, stderr: "rm: cannot remove '/tmp/pe.conf': Operation not permitted\n")
        end
        expect_out_message.with_params(
          "WARNING: /tmp/pe.conf may still be on primary (rm: cannot remove '/tmp/pe.conf': Operation not permitted). " \
          'Delete it by hand; on the primary it holds the console password.',
        )

        result = run_plan('peadm::subplans::install', install_params)

        expect(result).not_to be_ok
        expect(result.value.msg).to include('peadm::pe_install')
      end
    end

    it "warns with rm's error, but finishes the install, when /tmp/pe.conf can't be removed" do
      expect_command('rm -f /tmp/pe.conf').with_targets(['primary']).return do |targets:, command:, **|
        command_results(targets, command, exit_code: 1, stderr: "rm: cannot remove '/tmp/pe.conf': Operation not permitted\n")
      end
      expect_out_message.with_params(
        "WARNING: /tmp/pe.conf may still be on primary (rm: cannot remove '/tmp/pe.conf': Operation not permitted). " \
        'Delete it by hand; on the primary it holds the console password.',
      )

      expect(run_plan('peadm::subplans::install', install_params)).to be_ok
    end
  end
end
