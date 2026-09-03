require 'spec_helper'

describe 'peadm::convert_compiler_to_legacy' do
  include BoltSpec::Plans

  # OIDs from functions/oid.pp, inlined here rather than shelling out to the
  # real function, so a fixture typo is obvious by inspection. Methods
  # rather than constants: a bare constant assigned inside a describe block
  # leaks into Object (see spec/plans/subplans/configure_spec.rb's comment
  # on the same issue), which risks colliding with same-named constants in
  # other spec files running concurrently in this ticket.
  def avail_group_oid
    '1.3.6.1.4.1.34380.1.1.9813'
  end

  def pp_cluster_oid
    '1.3.6.1.4.1.34380.1.1.16'
  end

  def allow_standard_non_returning_calls
    allow_apply
    allow_out_message
    # peadm::modify_certificate is a *plan*, called 3x inside
    # background()/wait() (lines 108-134). Empirically confirmed (see PR
    # description / scratch run) that expect_plan's be_called_times + return
    # block correctly counts and captures calls made inside background()/
    # wait() for this plan -- BoltSpec's MockExecutor runs "futures"
    # synchronously (create_future evaluates the block immediately), so
    # there's no concurrency to race. Tests that don't care about the
    # specific modify_certificate calls just no-op it here, matching the
    # working pattern in convert_spec.rb.
    allow_plan('peadm::modify_certificate').always_return({})
  end

  # cluster.params shape consumed via getvar() in the plan. legacy_hosts here
  # is the *existing* legacy compiler list from cluster config -- distinct
  # from the legacy_hosts *plan parameter*, which is the set being converted
  # in this run ($convert_legacy_compiler_targets).
  def cluster(overrides = {})
    {
      'params' => {
        'replica_host' => nil,
        'primary_postgresql_host' => nil,
        'replica_postgresql_host' => nil,
        'compiler_hosts' => [],
        'legacy_hosts' => [],
      }.merge(overrides)
    }
  end

  let(:pe_rule_check_updated) { { 'updated' => true, 'message' => 'ok' } }

  # --------------------------------------------------------------------
  # 1. rules_check['updated'] == false -> fail_plan (lines ~12-15)
  # --------------------------------------------------------------------
  # A mutation that inverts the `unless` to `if`, or drops the fail_plan
  # entirely, would let the plan continue past this guard (and blow up much
  # later, or silently succeed) instead of failing fast with this message.
  it 'fails immediately if PE Master group rules have not been updated for pe_compiler_legacy' do
    expect_task('peadm::check_pe_master_rules').with_targets(['primary']).always_return(
      'updated' => false, 'message' => 'rules stale',
    )

    result = run_plan('peadm::convert_compiler_to_legacy',
                       'primary_host' => 'primary',
                       'legacy_hosts' => 'legacy1',
                       'node_group_environment' => 'production')

    expect(result).not_to be_ok
    expect(result.value.msg).to eq(
      'Please run the Convert plan to convert your Puppet infrastructure to be managed by this version of PEADM.',
    )
  end

  # --------------------------------------------------------------------
  # 2. cluster.error set -> fail_plan (lines ~17-21)
  # --------------------------------------------------------------------
  # A mutation that drops this check (or checks the wrong key) would let the
  # plan barrel ahead with a nil/garbage $cluster hash instead of surfacing
  # the task's own error message.
  it 'fails with the task-reported message if get_peadm_config returns an error' do
    expect_task('peadm::check_pe_master_rules').with_targets(['primary']).always_return(pe_rule_check_updated)
    expect_task('peadm::get_peadm_config').with_targets(['primary']).always_return(
      'error' => 'This is not a peadm-compatible cluster. Use peadm::convert first.',
    )

    result = run_plan('peadm::convert_compiler_to_legacy',
                       'primary_host' => 'primary',
                       'legacy_hosts' => 'legacy1',
                       'node_group_environment' => 'production')

    expect(result).not_to be_ok
    expect(result.value.msg).to eq('This is not a peadm-compatible cluster. Use peadm::convert first.')
  end

  # --------------------------------------------------------------------
  # 3. The 3-tier A/B availability-group fallback (lines ~74-106).
  #    Only exercised when arch['disaster-recovery'] is true, i.e. a
  #    replica_host is configured -- assert_supported_architecture.pp
  #    treats [primary, replica] presence as the DR signal.
  # --------------------------------------------------------------------
  describe 'availability-group assignment for converted targets (DR architecture)' do
    def allow_standard_dr_calls
      allow_apply
      allow_out_message
      allow_task('peadm::puppet_runonce')
      allow_any_command
      expect_task('peadm::check_pe_master_rules').with_targets(['primary']).always_return(pe_rule_check_updated)
    end

    # Tier 1: peadm_availability_group OID wins outright, even when
    # pp_cluster (tier 2) disagrees and index parity (tier 3) also
    # disagrees. filler0 sits at index 0 purely to push legacy-a1 to index 1,
    # where tier-3 fallback (1 % 2 != 0) would incorrectly say "B" -- so if
    # the code fell through past tier 1 for any reason (wrong precedence,
    # dropped elsif, off-by-one on the equality check), this test would see
    # legacy-a1 land in the B call instead of the A call.
    it 'assigns via peadm_availability_group when set to A or B, even if pp_cluster disagrees' do
      allow_standard_dr_calls
      expect_task('peadm::get_peadm_config').with_targets(['primary']).always_return(
        cluster('replica_host' => 'replica1'),
      )
      expect_task('peadm::cert_data').return_for_targets(
        'filler0'   => { 'extensions' => {} },
        'legacy-a1' => { 'extensions' => { avail_group_oid => 'A', pp_cluster_oid => 'B' } },
      ).be_called_times(1)

      captured = []
      expect_plan('peadm::modify_certificate').be_called_times(3).return do |params:, **|
        captured << params
        Bolt::PlanResult.new({}, 'success')
      end

      result = run_plan('peadm::convert_compiler_to_legacy',
                         'primary_host' => 'primary',
                         'legacy_hosts' => ['filler0', 'legacy-a1'],
                         'node_group_environment' => 'production')
      expect(result).to be_ok

      a_call = captured[1]
      b_call = captured[2]
      expect(Array(a_call['targets']).map(&:name)).to include('legacy-a1')
      expect(Array(b_call['targets']).map(&:name)).not_to include('legacy-a1')
    end

    # Tier 2: pp_cluster OID is used when peadm_availability_group is absent
    # or not A/B. legacy-b1 sits at index 0, where tier-3 fallback
    # (0 % 2 == 0) would incorrectly say "A" -- so a fallthrough past tier 2
    # (e.g. tier 2's elsif dropped, or checked against the wrong OID) would
    # surface as legacy-b1 landing in the A call instead of the B call.
    it 'falls back to pp_cluster when peadm_availability_group is absent or invalid' do
      allow_standard_dr_calls
      expect_task('peadm::get_peadm_config').with_targets(['primary']).always_return(
        cluster('replica_host' => 'replica1'),
      )
      expect_task('peadm::cert_data').return_for_targets(
        'legacy-b1' => { 'extensions' => { avail_group_oid => 'not-a-or-b', pp_cluster_oid => 'B' } },
        'filler1'   => { 'extensions' => {} },
      ).be_called_times(1)

      captured = []
      expect_plan('peadm::modify_certificate').be_called_times(3).return do |params:, **|
        captured << params
        Bolt::PlanResult.new({}, 'success')
      end

      result = run_plan('peadm::convert_compiler_to_legacy',
                         'primary_host' => 'primary',
                         'legacy_hosts' => ['legacy-b1', 'filler1'],
                         'node_group_environment' => 'production')
      expect(result).to be_ok

      a_call = captured[1]
      b_call = captured[2]
      expect(Array(b_call['targets']).map(&:name)).to include('legacy-b1')
      expect(Array(a_call['targets']).map(&:name)).not_to include('legacy-b1')
    end

    # Tier 3: with neither OID present/valid on either target, assignment
    # falls back to index parity ($index % 2 == 0 => A, else B). Both
    # parities are checked in the same test so an "always A" or "always B"
    # regression in the fallback is caught regardless of which target it
    # happens to look right for.
    it 'falls back to index parity (index % 2) when neither OID gives a valid A/B value' do
      allow_standard_dr_calls
      expect_task('peadm::get_peadm_config').with_targets(['primary']).always_return(
        cluster('replica_host' => 'replica1'),
      )
      expect_task('peadm::cert_data').return_for_targets(
        'legacy-c1a' => { 'extensions' => {} },
        'legacy-c1b' => { 'extensions' => { avail_group_oid => 'nope', pp_cluster_oid => 'nope' } },
      ).be_called_times(1)

      captured = []
      expect_plan('peadm::modify_certificate').be_called_times(3).return do |params:, **|
        captured << params
        Bolt::PlanResult.new({}, 'success')
      end

      result = run_plan('peadm::convert_compiler_to_legacy',
                         'primary_host' => 'primary',
                         'legacy_hosts' => ['legacy-c1a', 'legacy-c1b'],
                         'node_group_environment' => 'production')
      expect(result).to be_ok

      a_call = captured[1]
      b_call = captured[2]
      expect(Array(a_call['targets']).map(&:name)).to include('legacy-c1a')
      expect(Array(b_call['targets']).map(&:name)).to include('legacy-c1b')
      expect(Array(a_call['targets']).map(&:name)).not_to include('legacy-c1b')
      expect(Array(b_call['targets']).map(&:name)).not_to include('legacy-c1a')
    end
  end

  # --------------------------------------------------------------------
  # 4. remove_pdb gates two separate command blocks (lines ~137-140,
  #    ~147-154): stop/disable puppet+puppetdb before the puppet run, and
  #    purge the puppetdb package/user/dirs after.
  # --------------------------------------------------------------------
  describe 'remove_pdb command gating' do
    def run_with_remove_pdb(remove_pdb)
      allow_apply
      allow_out_message
      allow_plan('peadm::modify_certificate').always_return({})
      allow_task('peadm::puppet_runonce')
      expect_task('peadm::check_pe_master_rules').with_targets(['primary']).always_return(pe_rule_check_updated)
      expect_task('peadm::get_peadm_config').with_targets(['primary']).always_return(cluster)

      params = {
        'primary_host' => 'primary',
        'legacy_hosts' => 'legacy1',
        'node_group_environment' => 'production',
      }
      params['remove_pdb'] = remove_pdb unless remove_pdb.nil?

      yield

      run_plan('peadm::convert_compiler_to_legacy', params)
    end

    # A mutation that drops the `if $remove_pdb` guard (or inverts it) on
    # the stop/purge blocks would either always run them or never run them,
    # regardless of the parameter -- these two tests together pin both
    # failure directions down.
    it 'stops/disables puppet+puppetdb and purges puppetdb when remove_pdb is true (the default)' do
      result = run_with_remove_pdb(nil) do
        expect_command('puppet resource service puppet ensure=stopped').with_targets(['legacy1']).be_called_times(1)
        expect_command('puppet resource service pe-puppetdb ensure=stopped enable=false').with_targets(['legacy1']).be_called_times(1)
        expect_command('puppet resource package pe-puppetdb ensure=purged').with_targets(['legacy1']).be_called_times(1)
        expect_command('puppet resource user pe-puppetdb ensure=absent').with_targets(['legacy1']).be_called_times(1)
        expect_command('rm -rf /etc/puppetlabs/puppetdb').with_targets(['legacy1']).be_called_times(1)
        expect_command('rm -rf /var/log/puppetlabs/puppetdb').with_targets(['legacy1']).be_called_times(1)
        expect_command('rm -rf /opt/puppetlabs/server/data/puppetdb').with_targets(['legacy1']).be_called_times(1)
        expect_command('systemctl start pe-puppetserver.service').with_targets(['legacy1']).be_called_times(1)
        expect_command('puppet resource service puppet ensure=running').with_targets(['legacy1']).be_called_times(1)
      end

      expect(result).to be_ok
    end

    it 'skips the puppetdb stop/purge commands entirely when remove_pdb is false' do
      result = run_with_remove_pdb(false) do
        expect_command('puppet resource service puppet ensure=stopped').not_be_called
        expect_command('puppet resource service pe-puppetdb ensure=stopped enable=false').not_be_called
        expect_command('puppet resource package pe-puppetdb ensure=purged').not_be_called
        expect_command('puppet resource user pe-puppetdb ensure=absent').not_be_called
        expect_command('rm -rf /etc/puppetlabs/puppetdb').not_be_called
        expect_command('rm -rf /var/log/puppetlabs/puppetdb').not_be_called
        expect_command('rm -rf /opt/puppetlabs/server/data/puppetdb').not_be_called
        # The final restart commands are unconditional -- must still fire.
        expect_command('systemctl start pe-puppetserver.service').with_targets(['legacy1']).be_called_times(1)
        expect_command('puppet resource service puppet ensure=running').with_targets(['legacy1']).be_called_times(1)
      end

      expect(result).to be_ok
    end
  end

  # --------------------------------------------------------------------
  # 5. $compiler_targets = peadm::get_targets($compiler_hosts) -
  #    $convert_legacy_compiler_targets (line ~52): a host being converted
  #    to legacy must be removed from the "still a modern compiler" set.
  # --------------------------------------------------------------------
  # A mutation that swaps the subtraction for a union (or drops it) would
  # leave legacy1 in $compiler_targets, so it would show up in both the
  # modern-compiler modify_certificate/puppet_runonce call *and* the
  # legacy-side calls. with_targets(['compiler1']) below only matches a call
  # whose target set is *exactly* ['compiler1']; if legacy1 leaked in, that
  # stub would no longer match and the run would blow up with an
  # UnexpectedInvocation instead of quietly passing.
  it 'excludes a host being converted from $compiler_targets (modern compiler set)' do
    allow_standard_non_returning_calls
    allow_task('peadm::puppet_runonce')
    allow_any_command
    expect_task('peadm::check_pe_master_rules').with_targets(['primary']).always_return(pe_rule_check_updated)
    expect_task('peadm::get_peadm_config').with_targets(['primary']).always_return(
      cluster('compiler_hosts' => ['compiler1', 'legacy1']),
    )

    expect_task('peadm::puppet_runonce').with_targets(['compiler1']).be_called_times(1)

    captured = []
    expect_plan('peadm::modify_certificate').be_called_times(3).return do |params:, **|
      captured << params
      Bolt::PlanResult.new({}, 'success')
    end

    result = run_plan('peadm::convert_compiler_to_legacy',
                       'primary_host' => 'primary',
                       'legacy_hosts' => 'legacy1',
                       'node_group_environment' => 'production')

    expect(result).to be_ok
    modern_compiler_call = captured[0]
    expect(Array(modern_compiler_call['targets']).map(&:name)).to eq(['compiler1'])
  end
end
