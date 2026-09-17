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
end
