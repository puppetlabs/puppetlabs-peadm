require 'spec_helper'

# PE-44999: on extra-large-with-dr the replica has a dedicated PostgreSQL host
# (vars.role: replica-pdb-postgresql), so verify_replica has to confirm that
# replica_postgresql_host is configured as well as replica_host.
describe 'peadm_spec::verify_replica' do
  include BoltSpec::Plans

  let(:base_targets) do
    [
      { 'name' => 'primary', 'vars' => { 'role' => 'primary' } },
      { 'name' => 'replica', 'vars' => { 'role' => 'replica' } },
    ]
  end

  let(:xl_dr_targets) do
    base_targets + [
      { 'name' => 'primary-pg', 'vars' => { 'role' => 'primary-pdb-postgresql' } },
      { 'name' => 'replica-pg', 'vars' => { 'role' => 'replica-pdb-postgresql' } },
    ]
  end

  let(:inventory_data) { { 'targets' => targets } }

  let(:config_params) do
    {
      'primary_host'            => 'primary.example.com',
      'replica_host'            => 'replica.example.com',
      'primary_postgresql_host' => 'primary-pg.example.com',
      'replica_postgresql_host' => 'replica-pg.example.com',
    }
  end

  before(:each) do
    allow_out_message
    allow_task('peadm::get_peadm_config').always_return('params' => config_params)
  end

  context 'with an extra-large-with-dr inventory' do
    let(:targets) { xl_dr_targets }

    it 'succeeds when both the replica and its PostgreSQL host are configured' do
      expect(run_plan('peadm_spec::verify_replica', {})).to be_ok
    end

    it 'fails when the replica PostgreSQL host is not configured' do
      config_params['replica_postgresql_host'] = nil

      result = run_plan('peadm_spec::verify_replica', {})

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{No replica_postgresql_host})
    end

    it 'fails when the replica PostgreSQL host is an empty string' do
      config_params['replica_postgresql_host'] = ''

      result = run_plan('peadm_spec::verify_replica', {})

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{No replica_postgresql_host})
    end

    it 'fails when neither PostgreSQL host is configured' do
      config_params['primary_postgresql_host'] = nil
      config_params['replica_postgresql_host'] = nil

      result = run_plan('peadm_spec::verify_replica', {})

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{No replica_postgresql_host})
    end

    it 'fails when the replica PostgreSQL host is the primary PostgreSQL host' do
      config_params['replica_postgresql_host'] = config_params['primary_postgresql_host']

      result = run_plan('peadm_spec::verify_replica', {})

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{same as primary_postgresql_host})
    end

    it 'fails when the replica itself is not configured' do
      config_params['replica_host'] = nil

      result = run_plan('peadm_spec::verify_replica', {})

      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{No replica was found})
    end
  end

  # extra-large-and-spare-replica (test-add-replica-matrix.yaml) has a dedicated
  # primary PostgreSQL host but no replica-pdb-postgresql node, so the replica has
  # no PostgreSQL host of its own. That is a valid topology, not a failure.
  context 'with a split-database config but no replica-pdb-postgresql role in the inventory' do
    let(:targets) do
      base_targets + [{ 'name' => 'primary-pg', 'vars' => { 'role' => 'primary-pdb-postgresql' } }]
    end

    it 'does not require a replica PostgreSQL host' do
      config_params['replica_postgresql_host'] = nil

      expect(run_plan('peadm_spec::verify_replica', {})).to be_ok
    end
  end

  context 'with a standard-with-dr inventory and config' do
    let(:targets) { base_targets }

    it 'does not require a replica PostgreSQL host' do
      config_params['primary_postgresql_host'] = nil
      config_params['replica_postgresql_host'] = nil

      expect(run_plan('peadm_spec::verify_replica', {})).to be_ok
    end
  end
end
