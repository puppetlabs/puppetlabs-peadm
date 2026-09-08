require 'spec_helper'

describe 'peadm::convert' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  let(:trustedjson) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted_facts.json')))
  end

  let(:params) do
    { 'primary_host' => 'primary', 'legacy_compilers' => ['pe_compiler_legacy'] }
  end

  it 'single primary no dr valid' do
    allow_out_message
    allow_any_command
    allow_any_task
    allow_apply

    expect_task('peadm::cert_data').return_for_targets('primary' => trustedjson).be_called_times(2)
    expect_task('peadm::read_file').with_params('path' => '/opt/puppetlabs/server/pe_version').always_return({ 'content' => '2021.7.9' })
    expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
    expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })
    expect_task('peadm::node_group_unpin').with_targets('primary').with_params({ 'node_certnames' => ['pe_compiler_legacy'], 'group_name' => 'PE Master' })
    expect_task('peadm::check_legacy_compilers').with_targets('primary').with_params({ 'legacy_compilers' => 'pe_compiler_legacy' }).return_for_targets('primary' => { '_output' => '' })

    # For some reason, expect_plan() was not working??
    allow_plan('peadm::modify_certificate').always_return({})

    expect(run_plan('peadm::convert', params)).to be_ok
  end

  # Regression coverage for PE-43987: peadm::convert used to derive each
  # node's availability group ('A'/'B') purely from which plan parameter it
  # was passed as (primary_host => 'A', replica_host => 'B'), ignoring any
  # peadm_availability_group extension already on the node's certificate.
  # After a customer performs a role swap (via PE's switch_primary tooling,
  # outside this repo) and then runs convert, that overwrote the node's real
  # identity and corrupted the A/B topology.
  context 'availability group handling with a primary and replica' do
    let(:avail_group_oid) { '1.3.6.1.4.1.34380.1.1.9813' }
    let(:role_oid) { '1.3.6.1.4.1.34380.1.1.9812' }

    let(:primary_replica_params) do
      { 'primary_host' => 'primary', 'replica_host' => 'replica' }
    end

    def allow_standard_non_returning_calls
      allow_out_message
      allow_any_command
      allow_any_task
      allow_apply
    end

    before(:each) do
      allow_standard_non_returning_calls
      expect_task('peadm::read_file').with_params('path' => '/opt/puppetlabs/server/pe_version').always_return({ 'content' => '2021.7.9' })
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
    end

    # Records the availability group stamped onto each certname across all
    # peadm::modify_certificate invocations. Several of those invocations
    # (postgresql hosts, compilers) are no-ops in this primary/replica-only
    # scenario and carry an empty targets list; skip those.
    def capture_stamped_avail_groups(stamped)
      allow_plan('peadm::modify_certificate').return do |params:, **|
        targets = Array(params['targets'])
        unless targets.empty?
          certname = targets.first.name
          stamped[certname] = params['add_extensions'][avail_group_oid] if params['add_extensions']&.key?(avail_group_oid)
        end
        Bolt::PlanResult.new({}, 'success')
      end
    end

    it 'assigns primary=A/replica=B on a fresh conversion with no existing extensions' do
      expect_task('peadm::cert_data').return_for_targets(
        'primary' => { 'extensions' => {} },
        'replica' => { 'extensions' => {} },
      ).be_called_times(2)
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })

      stamped = {}
      capture_stamped_avail_groups(stamped)

      expect(run_plan('peadm::convert', primary_replica_params)).to be_ok
      expect(stamped['primary']).to eq('A')
      expect(stamped['replica']).to eq('B')
    end

    it 'preserves an existing availability group after a role swap instead of overwriting it by position' do
      # Simulate a prior role swap: 'primary' (now primary) already carries
      # the 'B' extension from before the swap, and 'replica' (now replica)
      # already carries 'A'.
      expect_task('peadm::cert_data').return_for_targets(
        'primary' => { 'extensions' => { avail_group_oid => 'B', role_oid => 'puppet/server' } },
        'replica' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/server' } },
      ).be_called_times(2)
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })

      stamped = {}
      capture_stamped_avail_groups(stamped)

      expect(run_plan('peadm::convert', primary_replica_params)).to be_ok
      expect(stamped['primary']).to eq('B')
      expect(stamped['replica']).to eq('A')
    end

    it 'fails fast when primary and replica already claim the same availability group' do
      expect_task('peadm::cert_data').return_for_targets(
        'primary' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/server' } },
        'replica' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/server' } },
      ).be_called_times(2)

      result = run_plan('peadm::convert', primary_replica_params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{both have availability group 'A'})
    end

    it 'fails fast when only one of primary/replica has an existing availability group extension' do
      expect_task('peadm::cert_data').return_for_targets(
        'primary' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/server' } },
        'replica' => { 'extensions' => {} },
      ).be_called_times(2)

      result = run_plan('peadm::convert', primary_replica_params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{inconsistent availability group state})
    end

    it 'still stamps the primary cert with its preserved group when there is no replica at all' do
      # No replica at all (Standard architecture). If the primary happens to
      # carry a leftover 'B' extension (e.g. it was a replica before a prior
      # role swap, and the old primary/replica has since been decommissioned),
      # there's no genuine pair to preserve, so peadm::convert must not
      # attempt to swap server_a_host/postgresql_a_host to the (nonexistent)
      # replica's certname -- doing so would resolve to undef, which
      # peadm::setup::node_manager requires to be a String[1] and would raise
      # a type-check error inside apply(). The cert stamping asserted here
      # still happens regardless of that logic (it's independent of it);
      # BoltSpec's allow_apply fully stubs the apply() block, so this suite
      # can't directly assert on the class parameters passed to
      # node_manager -- only that the plan completes and stamps certs as
      # expected. See PE-43987 review discussion.
      expect_task('peadm::cert_data').return_for_targets(
        'primary' => { 'extensions' => { avail_group_oid => 'B', role_oid => 'puppet/server' } },
      ).be_called_times(2)
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })

      stamped = {}
      capture_stamped_avail_groups(stamped)

      expect(run_plan('peadm::convert', { 'primary_host' => 'primary' })).to be_ok
      expect(stamped['primary']).to eq('B')
    end
  end

  # Regression coverage for PE-43987: the same positional-derivation bug, and
  # its fix, applies independently to the dedicated PostgreSQL hosts used in
  # the Extra Large architecture.
  context 'availability group handling with dedicated PostgreSQL hosts' do
    let(:avail_group_oid) { '1.3.6.1.4.1.34380.1.1.9813' }
    let(:role_oid) { '1.3.6.1.4.1.34380.1.1.9812' }

    let(:extra_large_params) do
      {
        'primary_host'             => 'primary',
        'replica_host'             => 'replica',
        'primary_postgresql_host'  => 'pg_primary',
        'replica_postgresql_host'  => 'pg_replica',
      }
    end

    def allow_standard_non_returning_calls
      allow_out_message
      allow_any_command
      allow_any_task
      allow_apply
    end

    before(:each) do
      allow_standard_non_returning_calls
      expect_task('peadm::read_file').with_params('path' => '/opt/puppetlabs/server/pe_version').always_return({ 'content' => '2021.7.9' })
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
    end

    def capture_stamped_avail_groups(stamped)
      allow_plan('peadm::modify_certificate').return do |params:, **|
        targets = Array(params['targets'])
        unless targets.empty?
          certname = targets.first.name
          stamped[certname] = params['add_extensions'][avail_group_oid] if params['add_extensions']&.key?(avail_group_oid)
        end
        Bolt::PlanResult.new({}, 'success')
      end
    end

    it 'assigns pg_primary=A/pg_replica=B on a fresh conversion with no existing extensions' do
      expect_task('peadm::cert_data').return_for_targets(
        'primary'    => { 'extensions' => {} },
        'replica'    => { 'extensions' => {} },
        'pg_primary' => { 'extensions' => {} },
        'pg_replica' => { 'extensions' => {} },
      ).be_called_times(2)
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })

      stamped = {}
      capture_stamped_avail_groups(stamped)

      expect(run_plan('peadm::convert', extra_large_params)).to be_ok
      expect(stamped['pg_primary']).to eq('A')
      expect(stamped['pg_replica']).to eq('B')
    end

    it 'preserves an existing PostgreSQL-host availability group after a role swap instead of overwriting it by position' do
      expect_task('peadm::cert_data').return_for_targets(
        'primary'    => { 'extensions' => {} },
        'replica'    => { 'extensions' => {} },
        'pg_primary' => { 'extensions' => { avail_group_oid => 'B', role_oid => 'puppet/puppetdb-database' } },
        'pg_replica' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/puppetdb-database' } },
      ).be_called_times(2)
      expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })

      stamped = {}
      capture_stamped_avail_groups(stamped)

      expect(run_plan('peadm::convert', extra_large_params)).to be_ok
      expect(stamped['pg_primary']).to eq('B')
      expect(stamped['pg_replica']).to eq('A')
    end

    it 'fails fast when the PostgreSQL primary and replica already claim the same availability group' do
      expect_task('peadm::cert_data').return_for_targets(
        'primary'    => { 'extensions' => {} },
        'replica'    => { 'extensions' => {} },
        'pg_primary' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/puppetdb-database' } },
        'pg_replica' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/puppetdb-database' } },
      ).be_called_times(2)

      result = run_plan('peadm::convert', extra_large_params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{both have availability group 'A'})
    end

    it 'fails fast when only one of the PostgreSQL primary/replica has an existing availability group extension' do
      expect_task('peadm::cert_data').return_for_targets(
        'primary'    => { 'extensions' => {} },
        'replica'    => { 'extensions' => {} },
        'pg_primary' => { 'extensions' => { avail_group_oid => 'A', role_oid => 'puppet/puppetdb-database' } },
        'pg_replica' => { 'extensions' => {} },
      ).be_called_times(2)

      result = run_plan('peadm::convert', extra_large_params)

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{inconsistent availability group state})
    end
  end
end
