require 'spec_helper'

# peadm::add_database manages live PE PostgreSQL topology changes (adding a new
# external PostgreSQL node to an L/XL deployment, either as the first node of a
# pair ("init" mode) or as the second node of an existing pair ("pair" mode)).
# A wrong-mode test that doesn't pin exact behavior could hide a bug that
# purges production databases on the wrong host, or skips a purge that should
# have happened. Every test below states the specific line(s)/behavior it
# pins and the failure mode it would catch.
describe 'peadm::add_database' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_apply
    allow_any_command
    allow_any_task
    # Force every run_plan() call made by add_database.pp to be explicitly
    # mocked. This means that if a mutation causes cleanup-db to call
    # db_purge/db_disable_pglogical when it shouldn't (or vice versa), the
    # test fails loudly (either via an explicit not_be_called assertion, or
    # via BoltSpec's "Unexpected call to run_plan(...)" error) instead of
    # silently executing the real sub-plan.
    execute_no_plan
    allow_out_message
    allow_out_verbose
  end

  def ok_plan_result
    Bolt::PlanResult.new({}, 'success')
  end

  # pe_version chosen to be below the 2023.8 threshold so peadm::pe_db_names()
  # returns exactly the 5 "original" database names, keeping expected values
  # concrete and easy to assert on exactly (not just "not empty").
  let(:pe_version) { '2023.0.0' }
  let(:default_params) { { 'targets' => 'new_db', 'primary_host' => 'primary' } }
  let(:target_db_purge) { ['pe-activity', 'pe-classifier', 'pe-inventory', 'pe-orchestrator', 'pe-rbac'] }

  # Baseline peadm_config: L/XL deployment (has a compiler), no replica, no
  # PostgreSQL nodes deployed yet (both role-letter/postgresql slots nil), and
  # the primary is assigned availability-group letter 'A' on the 'server'
  # role. Individual tests mutate a deep copy of this to exercise other
  # branches.
  def base_cfg
    {
      'pe_version' => pe_version,
      'params' => {
        'compilers' => ['compiler1'],
        'replica_host' => nil,
      },
      'role-letter' => {
        'server' => { 'A' => 'primary', 'B' => nil },
        'postgresql' => { 'A' => nil, 'B' => nil },
      },
    }
  end

  # Allows every sub-plan that a "happy path" run of add_database.pp calls,
  # returning success without asserting call counts/params. Individual tests
  # override specific plans with expect_plan(...) to make targeted
  # assertions, which take precedence because BoltSpec checks the
  # most-recently-registered matching stub first.
  def allow_all_subplans
    allow_plan('peadm::subplans::component_install').return { ok_plan_result }
    allow_plan('peadm::subplans::db_populate').return { ok_plan_result }
    allow_plan('peadm::util::update_classification').return { ok_plan_result }
    allow_plan('peadm::util::update_db_setting').return { ok_plan_result }
    allow_plan('peadm::util::db_purge').return { ok_plan_result }
    allow_plan('peadm::util::db_disable_pglogical').return { ok_plan_result }
  end

  # ---------------------------------------------------------------------
  # 1. fail_plan guard: add_database.pp is only usable on L/XL deployments
  #    (which have compilers). Line ~32-34:
  #      if $compilers.empty and !$is_migration {
  #        fail_plan('Plan peadm::add_database is only applicable for L and XL deployments')
  #      }
  # ---------------------------------------------------------------------

  # Catches: a mutation that removes/weakens this guard, letting a Standard
  # architecture deployment (no compilers) run this plan and start mutating
  # its single, in-band PostgreSQL instance as though it were an
  # externalized L/XL topology.
  it 'fail_plans when there are no compilers and this is not a migration (add_database.pp:32-34)' do
    allow_standard_non_returning_calls
    cfg = base_cfg
    cfg['params']['compilers'] = []
    expect_task('peadm::get_peadm_config').always_return(cfg)

    result = run_plan('peadm::add_database', default_params)

    expect(result).not_to be_ok
    expect(result.value.msg).to eq('Plan peadm::add_database is only applicable for L and XL deployments')
  end

  # Catches: a mutation that inverts `!$is_migration` (or drops the
  # is_migration escape hatch entirely), which would make a legitimate
  # migration - where compilers have not been added yet - fail_plan
  # incorrectly. Also pins the migration fallback on add_database.pp:73-76:
  #   $avail_group_letter = $calculated_group_letter ? {
  #     undef   => $is_migration ? { true => 'A', default => undef },
  #     default => $calculated_group_letter,
  #   }
  # by using a role-letter map where nothing matches $primary_host, so 'A'
  # can only come from the is_migration fallback.
  it 'does not fail_plan on a migration even with no compilers, and falls back to letter A (add_database.pp:32-34,73-76)' do
    allow_standard_non_returning_calls
    cfg = base_cfg
    cfg['params']['compilers'] = []
    cfg['role-letter']['server'] = { 'A' => 'someone_else', 'B' => nil }
    expect_task('peadm::get_peadm_config').always_return(cfg)

    captured_component_install = []
    expect_plan('peadm::subplans::component_install').be_called_times(1).return do |params:, **|
      captured_component_install << params
      ok_plan_result
    end
    expect_plan('peadm::subplans::db_populate').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::update_classification').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::update_db_setting').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::db_purge').be_called_times(2).return { ok_plan_result }

    result = run_plan('peadm::add_database', default_params.merge('is_migration' => true))

    expect(result).to be_ok
    expect(captured_component_install.first['avail_group_letter']).to eq('A')
  end

  # ---------------------------------------------------------------------
  # 2. Mode override vs auto-detection, add_database.pp:47-63.
  # ---------------------------------------------------------------------

  # Catches: a mutation that ignores the $mode parameter (always
  # auto-detecting instead). Uses a peadm_config that auto-detection would
  # read as "init" (no existing postgresql hosts), but explicitly forces
  # 'pair' via the mode param. If the override were ignored, cleanup-db
  # would purge databases (init-mode behavior); since it's honored,
  # cleanup-db must be skipped entirely (pair-mode behavior).
  it 'honors an explicit mode override even when auto-detection would choose differently (add_database.pp:47-63)' do
    allow_standard_non_returning_calls
    allow_all_subplans
    expect_task('peadm::get_peadm_config').always_return(base_cfg)

    expect_out_message.with_params('Operating mode overridden by parameter mode set to pair')
    expect_out_message.with_params('Operating in pair mode')
    expect_out_message.with_params('No databases to cleanup when in pair')
    expect_plan('peadm::util::db_purge').not_be_called
    expect_plan('peadm::util::db_disable_pglogical').not_be_called

    result = run_plan('peadm::add_database', default_params.merge('mode' => 'pair'))

    expect(result).to be_ok
  end

  # ---------------------------------------------------------------------
  # 3. Init-mode avail_group_letter derivation, add_database.pp:67-78.
  # ---------------------------------------------------------------------

  # Catches: a mutation that breaks the match between roles['server'] and
  # $primary_host (e.g. comparing the wrong keys, or always taking the first
  # letter). With the primary registered as letter 'A', the new PostgreSQL
  # node must be assigned to 'A' too, and update_classification must receive
  # postgresql_a_host set to the new host with postgresql_b_host left undef
  # (no replica in this scenario, so the single-branch classification call at
  # add_database.pp:147-154 applies).
  it 'in init mode, matches the new node to the letter already assigned to the primary (add_database.pp:67-78,147-154)' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_peadm_config').always_return(base_cfg)

    captured_component_install = []
    expect_plan('peadm::subplans::component_install').be_called_times(1).return do |params:, **|
      captured_component_install << params
      ok_plan_result
    end
    captured_classification = []
    expect_plan('peadm::util::update_classification').be_called_times(1).return do |params:, **|
      captured_classification << params
      ok_plan_result
    end
    expect_plan('peadm::subplans::db_populate').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::update_db_setting').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::db_purge').be_called_times(2).return { ok_plan_result }

    result = run_plan('peadm::add_database', default_params)

    expect(result).to be_ok
    expect(captured_component_install.first['avail_group_letter']).to eq('A')
    expect(captured_classification.first['postgresql_a_host']).to eq('new_db')
    expect(captured_classification.first['postgresql_b_host']).to be_nil
  end

  # Catches: a mutation that makes the "no match found" fallback always
  # return 'A' regardless of $is_migration (the counterpart to the
  # is_migration=true test above at add_database.pp:73-76). With no
  # role-letter entry matching $primary_host and is_migration left at its
  # default of false, $avail_group_letter must stay undef rather than
  # silently defaulting to 'A'.
  it 'in init mode, leaves avail_group_letter undef when no role matches and it is not a migration (add_database.pp:67-76)' do
    allow_standard_non_returning_calls
    cfg = base_cfg
    cfg['role-letter']['server'] = { 'A' => 'someone_else', 'B' => nil }
    expect_task('peadm::get_peadm_config').always_return(cfg)

    captured_component_install = []
    expect_plan('peadm::subplans::component_install').be_called_times(1).return do |params:, **|
      captured_component_install << params
      ok_plan_result
    end
    expect_plan('peadm::subplans::db_populate').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::update_classification').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::update_db_setting').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::db_purge').be_called_times(2).return { ok_plan_result }

    result = run_plan('peadm::add_database', default_params)

    expect(result).to be_ok
    expect(captured_component_install.first['avail_group_letter']).to be_nil
  end

  # ---------------------------------------------------------------------
  # 4. Pair-mode avail_group_letter/source_db_host derivation,
  #    add_database.pp:81-91.
  # ---------------------------------------------------------------------

  # Catches: a mutation that picks the wrong (already-occupied) letter, or
  # that computes source_db_host from the wrong side (e.g. returning the
  # node being added instead of "the other" existing node). With A occupied
  # by a different host and B vacant, the new node must be assigned to B and
  # sourced from A.
  it 'in pair mode, assigns the new node to the vacant letter and sources data from the other existing node (add_database.pp:81-91)' do
    allow_standard_non_returning_calls
    cfg = base_cfg
    cfg['role-letter']['postgresql'] = { 'A' => 'host_a', 'B' => nil }
    expect_task('peadm::get_peadm_config').always_return(cfg)

    captured_component_install = []
    expect_plan('peadm::subplans::component_install').be_called_times(1).return do |params:, **|
      captured_component_install << params
      ok_plan_result
    end
    captured_db_populate = []
    expect_plan('peadm::subplans::db_populate').be_called_times(1).return do |params:, **|
      captured_db_populate << params
      ok_plan_result
    end
    captured_classification = []
    expect_plan('peadm::util::update_classification').be_called_times(1).return do |params:, **|
      captured_classification << params
      ok_plan_result
    end
    expect_plan('peadm::util::update_db_setting').be_called_times(1).return { ok_plan_result }

    # Pair mode must skip cleanup-db entirely (add_database.pp:174-198) - a
    # regression here would purge/disable pglogical on a database pair that
    # is still mid-setup.
    expect_plan('peadm::util::db_purge').not_be_called
    expect_plan('peadm::util::db_disable_pglogical').not_be_called
    expect_out_message.with_params('No databases to cleanup when in pair')

    result = run_plan('peadm::add_database', default_params)

    expect(result).to be_ok
    expect(captured_component_install.first['avail_group_letter']).to eq('B')
    expect(captured_db_populate.first['source_host']).to eq('host_a')
    expect(captured_classification.first['postgresql_a_host']).to be_nil
    expect(captured_classification.first['postgresql_b_host']).to eq('new_db')
  end

  # Catches: a mutation that breaks the "replacement" branch of the letter
  # selection (`(! $v) or ($v == $postgresql_host)`), e.g. requiring the slot
  # to be strictly vacant. When the new node's own hostname is already
  # recorded under letter 'A' (a reinstall/replace scenario), it must be
  # re-assigned to 'A' (not skipped or assigned to 'B'), and source_db_host
  # must be the *other* node ('host_b'), never itself.
  it 'in pair mode, re-assigns a replaced node to its previous letter and sources from the other node (add_database.pp:81-91)' do
    allow_standard_non_returning_calls
    cfg = base_cfg
    cfg['role-letter']['postgresql'] = { 'A' => 'new_db', 'B' => 'host_b' }
    expect_task('peadm::get_peadm_config').always_return(cfg)

    captured_component_install = []
    expect_plan('peadm::subplans::component_install').be_called_times(1).return do |params:, **|
      captured_component_install << params
      ok_plan_result
    end
    captured_db_populate = []
    expect_plan('peadm::subplans::db_populate').be_called_times(1).return do |params:, **|
      captured_db_populate << params
      ok_plan_result
    end
    expect_plan('peadm::util::update_classification').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::update_db_setting').be_called_times(1).return { ok_plan_result }
    expect_plan('peadm::util::db_purge').not_be_called
    expect_plan('peadm::util::db_disable_pglogical').not_be_called

    result = run_plan('peadm::add_database', default_params)

    expect(result).to be_ok
    expect(captured_component_install.first['avail_group_letter']).to eq('A')
    expect(captured_db_populate.first['source_host']).to eq('host_b')
  end

  # ---------------------------------------------------------------------
  # 5/6. cleanup-db (add_database.pp:174-198) - the highest-value test in
  #      this file. A mutation that inverts the `$operating_mode == 'init'`
  #      check here would silently purge production databases in pair mode
  #      (while a pair member is still being populated), or silently skip
  #      the purge in init mode (leaving stale copied-over databases and old
  #      primary-hosted databases behind indefinitely).
  # ---------------------------------------------------------------------

  # Catches: init mode's purge logic not running at all, purging the wrong
  # set of databases from the wrong hosts, or not disabling pglogical when a
  # replica is absent (it must NOT be called at all in that case, since
  # add_database.pp:182-184 gates that call on $replica_host).
  it 'in init mode without a replica, cleanup-db purges databases but does not touch pglogical (add_database.pp:174-198,182-184)' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_peadm_config').always_return(base_cfg)

    allow_plan('peadm::subplans::component_install').return { ok_plan_result }
    allow_plan('peadm::subplans::db_populate').return { ok_plan_result }
    allow_plan('peadm::util::update_classification').return { ok_plan_result }
    allow_plan('peadm::util::update_db_setting').return { ok_plan_result }
    expect_plan('peadm::util::db_disable_pglogical').not_be_called

    captured_db_purge = []
    expect_plan('peadm::util::db_purge').be_called_times(2).return do |params:, **|
      captured_db_purge << params
      ok_plan_result
    end

    result = run_plan('peadm::add_database', default_params)

    expect(result).to be_ok
    databases_by_call = captured_db_purge.map { |p| p['databases'] }
    # One call purges the single legacy 'pe-puppetdb' database off of the
    # previous (primary-hosted, in init mode) backend...
    expect(databases_by_call).to include(['pe-puppetdb'])
    # ...and the other purges the full set of copied-over databases off of
    # the newly-added node.
    expect(databases_by_call).to include(target_db_purge)

    targets_by_call = captured_db_purge.map { |p| Array(p['targets']).map(&:name) }
    expect(targets_by_call.find { |t| t == ['new_db'] }).not_to be_nil
    expect(targets_by_call.find { |t| t.all? { |name| name == 'primary' } }).not_to be_nil
  end

  # Catches: the pglogical-disable call not being gated on $replica_host (or
  # being gated backwards), and the update-classification transitional
  # branch (add_database.pp:136-146) not activating when a replica exists -
  # both postgresql_a_host and postgresql_b_host must be set to the *same*
  # new host (so the alternate availability group can reach it), unlike the
  # no-replica case where only one of the two is set (see the init-mode
  # avail_group_letter test above).
  it 'in init mode with a replica, disables pglogical before purging and uses the transitional single-host classification (add_database.pp:182-184,136-146)' do
    allow_standard_non_returning_calls
    cfg = base_cfg
    cfg['params']['replica_host'] = 'replica_node'
    expect_task('peadm::get_peadm_config').always_return(cfg)

    allow_plan('peadm::subplans::component_install').return { ok_plan_result }
    allow_plan('peadm::subplans::db_populate').return { ok_plan_result }
    allow_plan('peadm::util::update_db_setting').return { ok_plan_result }
    allow_plan('peadm::util::db_purge').return { ok_plan_result }

    captured_pglogical = []
    expect_plan('peadm::util::db_disable_pglogical').be_called_times(1).return do |params:, **|
      captured_pglogical << params
      ok_plan_result
    end
    captured_classification = []
    expect_plan('peadm::util::update_classification').be_called_times(1).return do |params:, **|
      captured_classification << params
      ok_plan_result
    end

    result = run_plan('peadm::add_database', default_params)

    expect(result).to be_ok
    expect(captured_pglogical.first['databases']).to eq(target_db_purge)
    expect(Array(captured_pglogical.first['targets']).map(&:name)).to eq(['new_db'])

    # Transitional branch: both A and B point at the same new host, rather
    # than only the matching letter being set (contrast with the no-replica
    # test, where postgresql_b_host is nil).
    expect(captured_classification.first['postgresql_a_host']).to eq('new_db')
    expect(captured_classification.first['postgresql_b_host']).to eq('new_db')
  end
end
