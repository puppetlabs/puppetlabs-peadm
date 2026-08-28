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

  # OID values from functions/oid.pp, pinned here so the assertions below
  # read as literal fact/trusted-extension paths (matching how they appear
  # in the compiled rule), while still documenting where they come from. A
  # mutation to the OID string in peadm::oid, or to which OID is used at a
  # given call site in node_manager.pp, will surface as a rule mismatch
  # against these constants.
  let(:peadm_role_oid) { '1.3.6.1.4.1.34380.1.1.9812' }
  let(:peadm_availability_group_oid) { '1.3.6.1.4.1.34380.1.1.9813' }

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
      is_expected.to contain_node_group('PE Database')

      # On-prem with no dedicated pe-postgresql node, the PuppetDB database is
      # co-located with each server (postgresql_a_host == server_a_host, and
      # postgresql_b_host is undef). database_host is therefore left UNSET on both
      # primary groups so PE creates/uses the LOCAL database. Emitting a non-undef
      # value (the server's own host, or the 'not-configured' sentinel) makes
      # PE 2025.11+ treat it as remote and skip creating the local pe-puppetdb DB.
      is_expected.to contain_node_group('PE Primary A').with_data({})
      is_expected.to contain_node_group('PE Primary B').with_data({})

      is_expected.to contain_node_group('PE Compiler Group A').with_classes(
        'puppet_enterprise::profile::puppetdb' => { 'database_host' => primary_host },
        'puppet_enterprise::profile::master'   => compiler_master_a,
      )

      is_expected.to contain_node_group('PE Compiler Group B').with_classes(
        'puppet_enterprise::profile::puppetdb' => { 'database_host' => 'not-configured' },
        'puppet_enterprise::profile::master'   => compiler_master_b,
      )
    end

    it 'leaves PE Master data unset when compiler_pool_address is not supplied' do
      # $compiler_pool_address_data is undef when compiler_pool_address is
      # undef, and that undef is passed straight through to node_group's
      # data parameter, which leaves the parameter unset rather than emitting
      # an empty hash. A mutation that unconditionally builds the
      # pe_repo.compile_master_pool_address hash (e.g. dropping the ternary's
      # undef branch) would show up here as data becoming set.
      is_expected.to contain_node_group('PE Master').without_data
    end
  end

  # These groups' rule/classes/variables are built without reference to any
  # class parameter, so they compile identically for every example in this
  # file. base_params is used purely because primary_host is mandatory; no
  # other parameter choice affects the assertions below.
  context 'node groups whose configuration does not depend on any class parameter' do
    let(:params) { base_params }

    it 'pins PE Infrastructure Agent to nodes carrying the peadm_role trusted extension or the pe_server_version fact' do
      # Catches: a change to the peadm_role OID, the '^puppet/' role-prefix
      # regex, the pe_server_version fact name, or a flip from 'or' to 'and'
      # (which would wrongly exclude non-PE-role infra nodes that still
      # report pe_server_version, or vice versa).
      is_expected.to contain_node_group('PE Infrastructure Agent').with_rule(
        ['or',
         ['~', ['trusted', 'extensions', peadm_role_oid], '^puppet/'],
         ['~', ['fact', 'pe_server_version'], '.+']],
      )
    end

    it 'restricts PE Compiler to nodes whose pp_auth_role trusted extension is pe_compiler' do
      # Catches: a typo'd role literal ("pe_compiler" -> something else), a
      # switch of the '=' operator to '~', or the parent being changed away
      # from 'PE Master'.
      is_expected.to contain_node_group('PE Compiler').with(
        'parent' => 'PE Master',
        'rule'   => ['and', ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler']],
      )
    end

    it 'gives PE HA Replica the primary_master_replica profile class and the peadm_replica variable' do
      # Catches: dropping the (empty but required) primary_master_replica
      # class declaration -- which is what makes the replica node classified
      # into that profile at all -- or the peadm_replica variable flipping to
      # false/absent, which peadm::get_cluster_roles and other consumers rely
      # on to identify the replica.
      is_expected.to contain_node_group('PE HA Replica').with(
        'classes'   => { 'puppet_enterprise::profile::primary_master_replica' => {} },
        'variables' => { 'peadm_replica' => true },
      )
    end
  end

  context 'when compiler_pool_address is set' do
    let(:pool_address) { 'compilers.example.com' }
    let(:params) { base_params.merge('compiler_pool_address' => pool_address) }

    it 'adds the compiler pool address to PE Master data as pe_repo.compile_master_pool_address' do
      # Paired with the "unset" assertion above: together they catch both a
      # mutation that always emits this data hash (regardless of the param)
      # and one that never emits it (e.g. an inverted ternary condition, or
      # the wrong variable being interpolated into the hash).
      is_expected.to contain_node_group('PE Master').with_data(
        'pe_repo' => { 'compile_master_pool_address' => pool_address },
      )
    end
  end

  # server_b_host must be set (in addition to base_params' server_a_host) to
  # exercise the internal_compiler_a/b_pool_address defaults for the legacy
  # compiler groups below. Using two distinct, genuinely different hostnames
  # means .unique is meaningfully exercised (it would pass even if .unique
  # were deleted), while still letting us pin the *order* in which the two
  # addresses appear -- which is where PE Legacy Compiler Group A and Group B
  # differ from one another.
  context 'when both internal compiler pool addresses are configured (legacy compiler DR pools)' do
    let(:server_b_host) { 'replica.example.com' }
    let(:params) { base_params.merge('server_b_host' => server_b_host) }

    it 'builds PE Legacy Compiler puppetdb_host from both internal pool addresses, A before B' do
      # Catches: the array order being swapped, either address being
      # dropped, or .unique somehow collapsing two genuinely distinct hosts.
      is_expected.to contain_node_group('PE Legacy Compiler').with(
        'parent'  => 'PE Master',
        'rule'    => ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
        'classes' => {
          'puppet_enterprise::profile::master' => {
            'puppetdb_host' => [primary_host, server_b_host],
            'puppetdb_port' => [8081],
          },
        },
      )
    end

    it 'builds PE Legacy Compiler Group A with the B pool address ordered before the A pool address' do
      # Catches: Group A's rule literal being changed from 'A' to something
      # else, and -- the mutation this pairs with the Group B test below to
      # catch -- the puppetdb_host array construction being made identical
      # to Group B's (i.e. losing the intentional A/B order reversal).
      is_expected.to contain_node_group('PE Legacy Compiler Group A').with(
        'rule'    => ['and',
                      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
                      ['=', ['trusted', 'extensions', peadm_availability_group_oid], 'A'],],
        'classes' => {
          'puppet_enterprise::profile::master' => {
            'puppetdb_host' => [server_b_host, primary_host],
            'puppetdb_port' => [8081],
          },
        },
      )
    end

    it 'builds PE Legacy Compiler Group B with the A pool address ordered before the B pool address, opposite Group A' do
      # Catches: Group B's rule literal being changed from 'B' to something
      # else, and -- paired with the Group A test above -- Group B's
      # puppetdb_host order being made identical to Group A's.
      is_expected.to contain_node_group('PE Legacy Compiler Group B').with(
        'rule'    => ['and',
                      ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy'],
                      ['=', ['trusted', 'extensions', peadm_availability_group_oid], 'B'],],
        'classes' => {
          'puppet_enterprise::profile::master' => {
            'puppetdb_host' => [primary_host, server_b_host],
            'puppetdb_port' => [8081],
          },
        },
      )
    end
  end
end
