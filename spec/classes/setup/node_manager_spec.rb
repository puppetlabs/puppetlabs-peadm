require 'spec_helper'

describe 'peadm::setup::node_manager' do
  # spec_helper_local.rb calls BoltSpec::Plans.init, which sets
  # Puppet[:tasks] = true (Bolt's plan/script mode). In that mode the
  # initial manifest import treats resource statements as illegal,
  # blocking catalogue compilation for class specs. Restore catalog mode
  # for every example in this describe.
  before(:each) { Puppet[:tasks] = false }

  let(:primary_host) { 'primary.example.com' }
  let(:base_params) do
    {
      'primary_host'  => primary_host,
      'server_a_host' => primary_host,
    }
  end

  # PEADM's compiler-group classes property always carries both the puppetdb
  # entry (whose database_host is the value under test) and a master entry
  # that varies with the internal_compiler_*_pool_address parameters.
  # rspec-puppet's `.with_X` matcher compares for strict equality, not
  # partial match, so we provide the full expected hash here.
  let(:compiler_master_a) do
    {
      # In this fixture server_b_host is undef, so
      # internal_compiler_b_pool_address resolves to undef and is filtered.
      'puppetdb_host' => ["${trusted['certname']}"],
      'puppetdb_port' => [8081],
    }
  end
  let(:compiler_master_b) do
    {
      # server_a_host is set, so internal_compiler_a_pool_address resolves to it.
      'puppetdb_host' => ["${trusted['certname']}", primary_host],
      'puppetdb_port' => [8081],
    }
  end

  # WORKAROUND: the *first* catalogue compile in this rspec process fails with
  # "Resource type not found: Node_group" even though the node_manager
  # fixture's custom type is on the load path and in Puppet::Type's registry.
  # The cause is spec_helper_local.rb calling BoltSpec::Plans.init, which runs
  # Bolt::PAL.load_puppet and sets Puppet[:tasks] = true at load time. Bolt's
  # own source warns this is "probably not safe to do in modules that also
  # test Puppet manifest code" (bolt gem: lib/bolt_spec/plans.rb). That
  # initialisation leaves the environment's resource-type loader unable to
  # resolve the native type until one compile has run; the act of compiling
  # once repairs it for the remainder of the process.
  #
  # peadm is otherwise a Bolt-plan module, so this is its only catalogue
  # spec and the only place the contamination surfaces. A single throwaway
  # compile primes the loader for every example that follows -- only the very
  # first compile in the process is affected, not the first compile per
  # context, so granular examples below are safe.
  context 'warm-up to prime the contaminated resource-type loader' do
    let(:params) { base_params }

    it 'absorbs the first-compile failure caused by BoltSpec::Plans.init' do
      catalogue
    rescue StandardError
      # Intentionally swallowed; only the next compile onward matters.
    end
  end

  context 'when cloud_database_host is set' do
    let(:cloud_host) { 'cloud-sql.example.com' }
    let(:params) { base_params.merge('cloud_database_host' => cloud_host) }

    it 'routes all puppetdb database_host references to the cloud DB and omits the local-Postgres groups' do
      is_expected.not_to contain_node_group('PE Database')

      is_expected.to contain_node_group('PE Primary A').with_data(
        'puppet_enterprise::profile::primary_master_replica' => {
          'database_host_puppetdb' => cloud_host,
        },
      )

      is_expected.to contain_node_group('PE Primary B').with_data(
        'puppet_enterprise::profile::primary_master_replica' => {
          'database_host_puppetdb' => cloud_host,
        },
      )

      is_expected.to contain_node_group('PE Compiler Group A').with_classes(
        'puppet_enterprise::profile::puppetdb' => { 'database_host' => cloud_host },
        'puppet_enterprise::profile::master'   => compiler_master_a,
      )

      is_expected.to contain_node_group('PE Compiler Group B').with_classes(
        'puppet_enterprise::profile::puppetdb' => { 'database_host' => cloud_host },
        'puppet_enterprise::profile::master'   => compiler_master_b,
      )
    end
  end

  context 'in the default on-prem topology (cloud_database_host unset)' do
    let(:params) { base_params }

    it 'produces the expected classifier groups for an on-prem PostgreSQL topology' do
      # postgresql_b_host is undef in this fixture, so the b-side pick falls
      # through to the $notconf placeholder.
      is_expected.to contain_node_group('PE Database')

      is_expected.to contain_node_group('PE Primary A').with_data(
        'puppet_enterprise::profile::primary_master_replica' => {
          'database_host_puppetdb' => primary_host,
        },
        'puppet_enterprise::profile::puppetdb' => {
          'database_host' => primary_host,
        },
      )

      is_expected.to contain_node_group('PE Primary B').with_data(
        'puppet_enterprise::profile::primary_master_replica' => {
          'database_host_puppetdb' => 'not-configured',
        },
        'puppet_enterprise::profile::puppetdb' => {
          'database_host' => 'not-configured',
        },
      )

      is_expected.to contain_node_group('PE Compiler Group A').with_classes(
        'puppet_enterprise::profile::puppetdb' => { 'database_host' => primary_host },
        'puppet_enterprise::profile::master'   => compiler_master_a,
      )

      is_expected.to contain_node_group('PE Compiler Group B').with_classes(
        'puppet_enterprise::profile::puppetdb' => { 'database_host' => 'not-configured' },
        'puppet_enterprise::profile::master'   => compiler_master_b,
      )
    end
  end
end
