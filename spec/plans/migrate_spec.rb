# frozen_string_literal: true

require 'spec_helper'

# migrate.pp is a top-level orchestrator: it decides *which* of
# peadm::backup/install/restore/add_database/add_replica/upgrade to call and
# *with what params*, based on its own guard conditions and a $node_types
# reduction over the old cluster's config. These specs focus on those
# decision points rather than the mechanics of any individual sub-plan
# (those are covered by their own spec files).
describe 'peadm::migrate' do
  include BoltSpec::Plans

  let(:old_primary_host) { 'old_primary' }
  let(:license_path) { '/etc/puppetlabs/license.key' }
  let(:suite_license_path) { '/etc/puppetlabs/suite-license.lic' }
  let(:new_primary_host) { 'new_primary' }
  let(:backup_path) { '/tmp/mock-backup.tar.gz' }
  # A real file that exists on disk. upload_file() insists the source file
  # actually exists (Puppet::FileSystem.exist?) before handing off to the
  # mock executor, so the fake path produced by the default download stub
  # (which does not create a real file) would blow up here. Reusing this
  # fixture -- already used the same way in restore_spec.rb -- sidesteps
  # that without resorting to the Pathname/Tempfile double dance used
  # elsewhere in this repo for *uploads* of freshly-written local files.
  let(:downloaded_fixture_path) { File.expand_path(File.join(fixtures, 'peadm_config.json')) }
  let(:pe_version) { '2019.8.12' }

  # $cluster: populated from the FIRST run_task('peadm::get_peadm_config', ...)
  # call (migrate.pp lines ~53-64), used only for the pre-flight
  # assert_supported_architecture()/cluster.error checks. Kept as a minimally
  # valid "standard" architecture (primary only) everywhere except the
  # cluster-error test, so that check never fails by accident.
  let(:cluster_data) { { 'params' => { 'primary_host' => old_primary_host } } }

  # $old_pe_conf: populated from the SECOND run_task('peadm::get_peadm_config',
  # ...) call (migrate.pp line ~85), used to build $node_types / drive the
  # $nodes_to_purge reduction (lines ~102-123). Deliberately mocked as a
  # payload *separate* from cluster_data (see stub_get_peadm_config! below)
  # so the purge tests can freely set primary/replica/pg hosts to empty
  # without breaking the unrelated architecture assertion on $cluster.
  let(:old_pe_conf_params) do
    {
      'primary_host' => old_primary_host,
      'replica_host' => nil,
      'primary_postgresql_host' => nil,
      'replica_postgresql_host' => nil,
      'compilers' => nil,
      'legacy_compilers' => nil,
    }
  end
  let(:old_pe_conf) { { 'pe_version' => pe_version, 'params' => old_pe_conf_params } }

  # peadm::get_peadm_config is called twice on (effectively) the same
  # certname: once for $cluster, once for $old_pe_conf. return_for_targets
  # can't tell those two calls apart (same target name both times), so we
  # key the response off call order instead.
  def stub_get_peadm_config!
    call_count = 0
    allow_task('peadm::get_peadm_config').return do |targets:, **_kwargs|
      call_count += 1
      data = (call_count == 1) ? cluster_data : old_pe_conf
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: data) })
    end
  end

  def stub_precheck!
    allow_task('peadm::precheck').always_return({ 'platform' => 'el-9-x86_64' })
  end

  def stub_pe_conf_read!
    allow_task('peadm::read_file')
      .with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf')
      .always_return({ 'content' => '{}' })
  end

  # Stub the old primary's license file(s). A nil content mirrors the
  # real peadm::read_file task, which returns content => null (plus an
  # error) for a missing or unreadable file instead of failing.
  def stub_license_files!(license_key: nil, suite_license: nil)
    {
      license_path => license_key,
      suite_license_path => suite_license,
    }.each do |path, content|
      allow_task('peadm::read_file')
        .with_targets([old_primary_host])
        .with_params('path' => path, '_catch_errors' => true)
        .always_return({ 'content' => content })
    end
  end

  def stub_backup_download_upload!
    allow_plan('peadm::backup').always_return({ 'path' => backup_path })

    allow_download(backup_path).return do |targets:, **_kwargs|
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: { 'path' => downloaded_fixture_path }) })
    end

    allow_any_upload
  end

  # Everything migrate.pp needs to reach the end of the plan, with commands
  # left wide open (allow_any_command). Individual tests layer expect_plan/
  # expect_command/expect_out_message assertions on top of this.
  def stub_full_flow!
    allow_out_message
    allow_any_command
    stub_precheck!
    stub_pe_conf_read!
    stub_license_files!
    stub_backup_download_upload!
    stub_get_peadm_config!
    allow_plan('peadm::install').always_return({})
    allow_plan('peadm::restore').always_return({})
    allow_plan('peadm::add_database').always_return({})
    allow_plan('peadm::add_replica').always_return({})
    allow_plan('peadm::upgrade').always_return({})
  end

  # Same as stub_full_flow!, but leaves `hostname`/`puppet agent --enable`/
  # purge commands to be asserted explicitly instead of blanket-allowed, for
  # the nodes_to_purge tests where the whole point is which commands get run.
  def stub_full_flow_without_commands!
    allow_out_message
    allow_command('hostname')
    allow_command('puppet agent --enable')
    stub_precheck!
    stub_pe_conf_read!
    stub_license_files!
    stub_backup_download_upload!
    stub_get_peadm_config!
    allow_plan('peadm::install').always_return({})
    allow_plan('peadm::restore').always_return({})
    allow_plan('peadm::add_database').always_return({})
    allow_plan('peadm::add_replica').always_return({})
    allow_plan('peadm::upgrade').always_return({})
  end

  def base_params
    { 'old_primary_host' => old_primary_host, 'new_primary_host' => new_primary_host }
  end

  # --------------------------------------------------------------------
  # 1. cluster.error -> fail_plan (lines ~53-57), same guard pattern as
  #    restore.pp / convert_compiler_to_legacy.pp.
  #
  # Deliberately does NOT call stub_full_flow!: only enough is mocked to
  # reach the guard (out::message + the `hostname` connectivity check). If
  # the guard were dropped or checked the wrong key, the plan would barrel
  # on into peadm::precheck, which is *not* mocked here, so the test would
  # fail loudly via UnexpectedInvocation instead of silently passing.
  # --------------------------------------------------------------------
  describe 'cluster validation' do
    it 'fails fast via fail_plan with the task-reported message when the old cluster is invalid' do
      allow_out_message
      allow_command('hostname')
      expect_task('peadm::get_peadm_config')
        .with_targets([old_primary_host])
        .always_return({ 'error' => 'This is not a peadm-compatible cluster. Use peadm::convert first.' })

      result = run_plan('peadm::migrate', base_params)

      expect(result).not_to be_ok
      expect(result.value.kind).to eq('bolt/plan-failure')
      expect(result.value.msg).to eq('This is not a peadm-compatible cluster. Use peadm::convert first.')
    end
  end

  # --------------------------------------------------------------------
  # 2. upgrade_version gates both assert_supported_pe_version (top of the
  #    plan, lines ~35-38) and the final run_plan('peadm::upgrade', ...)
  #    call (lines ~164-173).
  # --------------------------------------------------------------------
  describe 'upgrade_version gating' do
    # Exercises the top-of-plan guard in isolation: an unsupported version
    # must blow up in assert_supported_pe_version() before the plan ever
    # gets as far as the `hostname` connectivity check (nothing beyond
    # allow_out_message is mocked, so any further progress would surface
    # as an UnexpectedInvocation).
    it 'fails fast when upgrade_version is set to an unsupported PE version' do
      allow_out_message

      result = run_plan('peadm::migrate', base_params.merge('upgrade_version' => '1.0.0'))

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{does not support PE 1\.0\.0})
    end

    # A mutation that flips `$upgrade_version and $upgrade_version != '' and
    # !empty($upgrade_version)` to always-true (or drops the guard) would
    # call peadm::upgrade with an undef/blank version; catch that by
    # asserting zero calls when the param is left at its default.
    it 'never calls peadm::upgrade when upgrade_version is not given' do
      stub_full_flow!
      expect_plan('peadm::upgrade').not_be_called

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    # Same guard, exercised via the explicit blank-string branch of the
    # condition (`$upgrade_version != ''`) rather than the undef default.
    it 'never calls peadm::upgrade when upgrade_version is an empty string' do
      stub_full_flow!
      expect_plan('peadm::upgrade').not_be_called

      expect(run_plan('peadm::migrate', base_params.merge('upgrade_version' => ''))).to be_ok
    end

    # A mutation that hardcodes/loses the version when forwarding to
    # peadm::upgrade would still leave this test's plan-level "was it
    # called at all" assertion green with a weaker check; asserting the
    # forwarded value equals the input exactly catches that.
    it 'runs assert_supported_pe_version and forwards upgrade_version unchanged to peadm::upgrade when set' do
      stub_full_flow!
      expect_plan('peadm::upgrade').return do |params:, **_kwargs|
        expect(params['version']).to eq('2023.8.10')
        expect(params['primary_host']).to eq(new_primary_host)
        expect(params['download_mode']).to eq('direct')
        Bolt::PlanResult.new({}, 'success')
      end

      expect(run_plan('peadm::migrate', base_params.merge('upgrade_version' => '2023.8.10'))).to be_ok
    end
  end

  # --------------------------------------------------------------------
  # 3. $nodes_to_purge reduction (lines ~102-123) and the purge/no-purge
  #    branch that follows it (lines ~127-135).
  # --------------------------------------------------------------------
  describe 'nodes_to_purge' do
    # A mutation that pushes the Array itself (`$memo + [$value]`) instead
    # of flattening it (`$memo + $value.filter { ... }`) would purge a
    # single malformed "node" (Ruby's stringified array) instead of two
    # real hostnames; asserting both individual purge commands run catches
    # that.
    context 'when a node_type value is an Array (e.g. legacy_compilers)' do
      let(:old_pe_conf_params) do
        {
          'primary_host' => nil,
          'replica_host' => nil,
          'primary_postgresql_host' => nil,
          'replica_postgresql_host' => nil,
          'compilers' => nil,
          'legacy_compilers' => ['legacy1', 'legacy2'],
        }
      end

      it 'purges every element of the array individually' do
        stub_full_flow_without_commands!
        expect_out_message.with_params('Purging nodes from old configuration individually')
        expect_command('/opt/puppetlabs/bin/puppet node purge legacy1')
        expect_command('/opt/puppetlabs/bin/puppet node purge legacy2')

        expect(run_plan('peadm::migrate', base_params)).to be_ok
      end
    end

    # A mutation that wraps the scalar branch in an extra array
    # (`$memo + [[$value]]`) or otherwise mishandles the non-Array `else`
    # would either purge a malformed node or purge nothing; asserting
    # exactly one purge command for the exact hostname catches both.
    context 'when a node_type value is a scalar hostname' do
      let(:old_pe_conf_params) do
        {
          'primary_host' => old_primary_host,
          'replica_host' => nil,
          'primary_postgresql_host' => nil,
          'replica_postgresql_host' => nil,
          'compilers' => nil,
          'legacy_compilers' => nil,
        }
      end

      it 'purges the scalar value as a single node' do
        stub_full_flow_without_commands!
        expect_out_message.with_params('Purging nodes from old configuration individually')
        expect_command("/opt/puppetlabs/bin/puppet node purge #{old_primary_host}")

        expect(run_plan('peadm::migrate', base_params)).to be_ok
      end
    end

    # A mutation that inverts `if !empty($nodes_to_purge)` (or always takes
    # the purge branch) would either skip a real purge or run
    # `puppet node purge` with no/garbage arguments here; since no purge
    # command is stubbed at all in this test, either mistake surfaces as
    # an UnexpectedInvocation, and the message assertion pins down the
    # intended "nothing to purge" branch.
    context 'when every node_type value is empty' do
      let(:old_pe_conf_params) do
        {
          'primary_host' => nil,
          'replica_host' => nil,
          'primary_postgresql_host' => nil,
          'replica_postgresql_host' => nil,
          'compilers' => nil,
          'legacy_compilers' => nil,
        }
      end

      it 'takes the "nothing to purge" path and issues zero purge commands' do
        stub_full_flow_without_commands!
        expect_out_message.with_params('No nodes to purge from old configuration')
        expect_out_message.with_params('Purging nodes from old configuration individually').not_be_called

        expect(run_plan('peadm::migrate', base_params)).to be_ok
      end
    end
  end

  # --------------------------------------------------------------------
  # 4. $primary_postgresql_host / $replica_postgresql_host gate
  #    peadm::add_database (lines ~138-150). The replica_postgresql_host
  #    call is nested *inside* the primary_postgresql_host branch, so it
  #    must never fire on its own.
  # --------------------------------------------------------------------
  describe 'add_database' do
    it 'calls add_database once for primary_postgresql_host when only that is set' do
      stub_full_flow!
      expect_plan('peadm::add_database').be_called_times(1).return do |params:, **_kwargs|
        expect(params['targets']).to eq('new_pg_primary')
        expect(params['primary_host']).to eq(new_primary_host)
        expect(params['is_migration']).to eq(true)
        Bolt::PlanResult.new({}, 'success')
      end

      params = base_params.merge('primary_postgresql_host' => 'new_pg_primary')
      expect(run_plan('peadm::migrate', params)).to be_ok
    end

    it 'calls add_database twice, primary then replica, when both are set' do
      stub_full_flow!
      call_targets = []
      expect_plan('peadm::add_database').be_called_times(2).return do |params:, **_kwargs|
        call_targets << params['targets']
        expect(params['primary_host']).to eq(new_primary_host)
        expect(params['is_migration']).to eq(true)
        Bolt::PlanResult.new({}, 'success')
      end

      params = base_params.merge(
        'primary_postgresql_host' => 'new_pg_primary',
        'replica_postgresql_host' => 'new_pg_replica',
      )
      expect(run_plan('peadm::migrate', params)).to be_ok
      expect(call_targets).to eq(['new_pg_primary', 'new_pg_replica'])
    end

    # This is the mutation-critical case: if the nested
    # `if $replica_postgresql_host { ... }` were flattened into a sibling
    # `if`, this call would incorrectly trigger add_database even though
    # primary_postgresql_host was never set.
    it 'never calls add_database when only replica_postgresql_host is set without primary_postgresql_host' do
      stub_full_flow!
      expect_plan('peadm::add_database').not_be_called

      params = base_params.merge('replica_postgresql_host' => 'new_pg_replica')
      expect(run_plan('peadm::migrate', params)).to be_ok
    end
  end

  # --------------------------------------------------------------------
  # 5. $replica_host gates peadm::add_replica (lines ~153-159), forwarding
  #    $replica_postgresql_host (possibly unset) alongside it.
  # --------------------------------------------------------------------
  describe 'add_replica' do
    it 'calls add_replica with the replica host and replica_postgresql_host forwarded when both are set' do
      stub_full_flow!
      expect_plan('peadm::add_replica').be_called_times(1).return do |params:, **_kwargs|
        expect(params['primary_host']).to eq(new_primary_host)
        expect(params['replica_host']).to eq('new_replica')
        expect(params['replica_postgresql_host']).to eq('new_pg_replica')
        Bolt::PlanResult.new({}, 'success')
      end

      params = base_params.merge('replica_host' => 'new_replica', 'replica_postgresql_host' => 'new_pg_replica')
      expect(run_plan('peadm::migrate', params)).to be_ok
    end

    it 'calls add_replica with replica_postgresql_host left unset when not provided' do
      stub_full_flow!
      expect_plan('peadm::add_replica').be_called_times(1).return do |params:, **_kwargs|
        expect(params['replica_host']).to eq('new_replica')
        expect(params['replica_postgresql_host']).to be_nil
        Bolt::PlanResult.new({}, 'success')
      end

      params = base_params.merge('replica_host' => 'new_replica')
      expect(run_plan('peadm::migrate', params)).to be_ok
    end

    it 'never calls add_replica when replica_host is not set' do
      stub_full_flow!
      expect_plan('peadm::add_replica').not_be_called

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end
  end

  # --------------------------------------------------------------------
  # 6. License handling. migrate.pp must hand peadm::install a license so
  #    the new primary isn't left unlicensed: an operator-supplied one wins,
  #    otherwise the old primary's is copied across, and a missing license
  #    is not an error.
  # --------------------------------------------------------------------
  describe 'license' do
    let(:install_error_msg) { 'No Python version 2 or 3 interpreter found.' }

    def expect_install_license(content:)
      expect_plan('peadm::install').be_called_times(1).return do |params:, **_kwargs|
        expect(params['license_key_content']).to eq(content)
        # migrate resolves the license itself and only ever hands install content
        expect(params).not_to have_key('license_key_file')
        Bolt::PlanResult.new({}, 'success')
      end
    end

    def expect_no_old_primary_license_read
      [license_path, suite_license_path].each do |path|
        expect_task('peadm::read_file').with_params('path' => path, '_catch_errors' => true).not_be_called
      end
    end

    def expect_license_message(source, prefix: '')
      expect_out_message.with_params("#{prefix}PE license for the new primary: #{source}")
    end

    # The no-license outcome is repeated once the migration has finished, so it
    # is not lost among the progress output of a long migration. BoltSpec cannot
    # assert message order, so only the message itself is checked.
    def expect_unlicensed_reminder
      expect_out_message.with_params('Warning: migration finished but no license key was installed on the new primary')
    end

    # BoltSpec compares out::message stubs with ==, so use a matcher object
    # that "equals" any message containing the given text.
    def message_containing(text)
      matcher = Object.new
      matcher.define_singleton_method(:to_str) { "message-containing-#{text}" }
      matcher.define_singleton_method(:==) { |message| message.to_s.include?(text) }
      matcher
    end

    def stub_license_read_failure!
      [license_path, suite_license_path].each do |path|
        allow_task('peadm::read_file')
          .with_targets([old_primary_host])
          .with_params('path' => path, '_catch_errors' => true)
          .error_with({ 'msg' => install_error_msg, 'kind' => 'puppetlabs.tasks/task-error' })
      end
    end

    # Positive control for message_containing: without it, a change in how
    # BoltSpec compares messages could make every not_be_called below pass
    # vacuously.
    it 'has a leak matcher that flags messages containing the text and only those' do
      matcher = message_containing('SECRET')
      leaking = 'x SECRET y'
      harmless = 'x harmless y'
      # String#== defers to the matcher's own == for a to_str object, which is
      # the comparison BoltSpec makes between a message and a stub's params.
      expect(leaking == matcher).to be(true)
      expect(harmless == matcher).to be(false)
    end

    it 'copies the license from the old primary when none is given' do
      stub_full_flow!
      stub_license_files!(license_key: 'OLD-PRIMARY-LICENSE')
      expect_install_license(content: 'OLD-PRIMARY-LICENSE')
      expect_license_message('/etc/puppetlabs/license.key on the old primary')

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'falls back to suite-license.lic when license.key is absent on the old primary' do
      stub_full_flow!
      stub_license_files!(suite_license: 'OLD-SUITE-LICENSE')
      expect_install_license(content: 'OLD-SUITE-LICENSE')
      expect_license_message('/etc/puppetlabs/suite-license.lic on the old primary')

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'carries on with no license when the old primary has none' do
      stub_full_flow!
      stub_license_files!
      expect_install_license(content: nil)
      expect_license_message('none found or readable, the new primary will be installed without a license key', prefix: 'Warning: ')
      expect_unlicensed_reminder

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'does not print the unlicensed reminder when a license was carried over' do
      stub_full_flow!
      stub_license_files!(license_key: 'OLD-PRIMARY-LICENSE')
      expect_install_license(content: 'OLD-PRIMARY-LICENSE')
      expect_out_message.with_params('Warning: migration finished but no license key was installed on the new primary').not_be_called

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'passes license_key_content through and does not read the old primary when given' do
      stub_full_flow!
      expect_no_old_primary_license_read
      expect_install_license(content: 'NEW-LICENSE')
      expect_license_message('operator-supplied')

      params = base_params.merge('license_key_content' => 'NEW-LICENSE')
      expect(run_plan('peadm::migrate', params)).to be_ok
    end

    it 'passes the contents of license_key_file to install and does not read the old primary' do
      stub_full_flow!
      expect_no_old_primary_license_read
      expect_install_license(content: "FILE-LICENSE\n")
      expect_license_message('operator-supplied')

      Tempfile.create('license.key') do |f|
        f.write("FILE-LICENSE\n")
        f.flush
        params = base_params.merge('license_key_file' => f.path)
        expect(run_plan('peadm::migrate', params)).to be_ok
      end
    end

    it 'fails before touching any host when both license_key_file and license_key_content are given' do
      allow_out_message
      expect_command('hostname').not_be_called

      params = base_params.merge('license_key_file' => '/path/to/license.key', 'license_key_content' => 'X')
      result = run_plan('peadm::migrate', params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{either one or neither of license_key_file and license_key_content})
    end

    # An operator who supplies a license expects that license, not a silent
    # substitution of the old primary's, so an empty value is an error.
    it 'fails before touching any host when license_key_content is given but empty' do
      allow_out_message
      expect_command('hostname').not_be_called

      result = run_plan('peadm::migrate', base_params.merge('license_key_content' => ''))

      expect(result).not_to be_ok
      expect(result.value.msg).to eq('license_key_content was given but is empty or blank')
    end

    it 'fails before touching any host when license_key_content is only whitespace' do
      allow_out_message
      expect_command('hostname').not_be_called

      result = run_plan('peadm::migrate', base_params.merge('license_key_content' => " \n"))

      expect(result).not_to be_ok
      expect(result.value.msg).to eq('license_key_content was given but is empty or blank')
    end

    it 'fails before touching any host when license_key_file does not exist' do
      allow_out_message
      expect_command('hostname').not_be_called

      result = run_plan('peadm::migrate', base_params.merge('license_key_file' => '/nonexistent/license.key'))

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{/nonexistent/license\.key})
    end

    it 'fails before touching any host when license_key_file is given but empty' do
      allow_out_message
      expect_command('hostname').not_be_called

      Tempfile.create('license.key') do |f|
        result = run_plan('peadm::migrate', base_params.merge('license_key_file' => f.path))

        expect(result).not_to be_ok
        expect(result.value.msg).to eq('license_key_file was given but is empty or blank')
      end
    end

    it 'fails before touching any host when license_key_file contains only whitespace' do
      allow_out_message
      expect_command('hostname').not_be_called

      Tempfile.create('license.key') do |f|
        f.write("  \n")
        f.flush
        result = run_plan('peadm::migrate', base_params.merge('license_key_file' => f.path))

        expect(result).not_to be_ok
        expect(result.value.msg).to eq('license_key_file was given but is empty or blank')
      end
    end

    it 'treats an empty license.key as missing and falls back to suite-license.lic' do
      stub_full_flow!
      stub_license_files!(license_key: '', suite_license: 'OLD-SUITE-LICENSE')
      expect_install_license(content: 'OLD-SUITE-LICENSE')

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'treats a whitespace-only license.key as missing and falls back to suite-license.lic' do
      stub_full_flow!
      stub_license_files!(license_key: " \n", suite_license: 'OLD-SUITE-LICENSE')
      expect_install_license(content: 'OLD-SUITE-LICENSE')

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'treats a whitespace-only suite-license.lic as missing' do
      stub_full_flow!
      stub_license_files!(license_key: '', suite_license: " \n")
      expect_install_license(content: nil)
      expect_license_message('none found or readable, the new primary will be installed without a license key', prefix: 'Warning: ')

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'passes no license when both old-primary license files are empty' do
      stub_full_flow!
      stub_license_files!(license_key: '', suite_license: '')
      expect_install_license(content: nil)

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    # peadm::read_file exits non-zero when the target has no python at all;
    # that must not abort a migration over an optional license, but the
    # operator must be told the read failed rather than that no license exists.
    it 'carries on with no license and reports the failure when reading the old primary license fails' do
      stub_full_flow!
      stub_license_read_failure!
      expect_install_license(content: nil)
      expect_out_message.with_params("Could not read #{license_path} on the old primary: #{install_error_msg}")
      expect_out_message.with_params("Could not read #{suite_license_path} on the old primary: #{install_error_msg}")
      expect_license_message('none found or readable, the new primary will be installed without a license key', prefix: 'Warning: ')
      expect_unlicensed_reminder

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    # A task failure on license.key must not stop the suite-license.lic fallback.
    it 'falls back to suite-license.lic when reading license.key fails' do
      stub_full_flow!
      allow_task('peadm::read_file')
        .with_targets([old_primary_host])
        .with_params('path' => license_path, '_catch_errors' => true)
        .error_with({ 'msg' => install_error_msg, 'kind' => 'puppetlabs.tasks/task-error' })
      allow_task('peadm::read_file')
        .with_targets([old_primary_host])
        .with_params('path' => suite_license_path, '_catch_errors' => true)
        .always_return({ 'content' => 'OLD-SUITE-LICENSE' })
      expect_install_license(content: 'OLD-SUITE-LICENSE')
      expect_out_message.with_params("Could not read #{license_path} on the old primary: #{install_error_msg}")
      expect_license_message('/etc/puppetlabs/suite-license.lic on the old primary')

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'never writes the license to plan output when copying it from the old primary' do
      stub_full_flow!
      stub_license_files!(license_key: 'OLD-PRIMARY-LICENSE')
      expect_install_license(content: 'OLD-PRIMARY-LICENSE')
      expect_out_message.with_params(message_containing('OLD-PRIMARY-LICENSE')).not_be_called

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    # A task that succeeds but returns something that is not license text must
    # be treated as "no license", not passed on to install.
    it 'treats a non-string content result from the old primary as no license' do
      stub_full_flow!
      stub_license_files!(license_key: 12_345, suite_license: 12_345)
      expect_install_license(content: nil)
      expect_license_message('none found or readable, the new primary will be installed without a license key', prefix: 'Warning: ')

      expect(run_plan('peadm::migrate', base_params)).to be_ok
    end

    it 'fails before touching any host when license_key_file is a directory' do
      allow_out_message
      expect_command('hostname').not_be_called

      Dir.mktmpdir('license-dir') do |dir|
        result = run_plan('peadm::migrate', base_params.merge('license_key_file' => dir))

        expect(result).not_to be_ok
        expect(result.value.msg).to include(dir)
      end
    end

    # Guards peadm::log_plan_parameters for the file parameter too: it would only
    # log a path, but the license params are kept out of that hash on purpose.
    it 'never writes the license_key_file path to plan output' do
      stub_full_flow!
      expect_install_license(content: "FILE-LICENSE\n")

      Tempfile.create('license-marker-path.key') do |f|
        f.write("FILE-LICENSE\n")
        f.flush
        expect_out_message.with_params(message_containing(File.basename(f.path))).not_be_called

        expect(run_plan('peadm::migrate', base_params.merge('license_key_file' => f.path))).to be_ok
      end
    end

    # Guards peadm::log_plan_parameters, which prints values unmasked: adding
    # the license params to the hash migrate logs would show up here.
    it 'never writes an operator-supplied license to plan output' do
      stub_full_flow!
      expect_install_license(content: 'NEW-LICENSE')
      expect_out_message.with_params(message_containing('NEW-LICENSE')).not_be_called

      params = base_params.merge('license_key_content' => 'NEW-LICENSE')
      expect(run_plan('peadm::migrate', params)).to be_ok
    end
  end
end
