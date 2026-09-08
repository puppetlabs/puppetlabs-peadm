require 'spec_helper'
require_relative '../../../tasks/get_peadm_config'

describe GetPEAdmConfig do
  # initialize(params) is a no-op today -- this task takes no meaningful
  # params of its own (call sites only ever pass Bolt's `_catch_errors`
  # control option, never task-level params); constructing with {} here is
  # equivalent to any other input.
  subject(:task) { described_class.new({}) }

  describe GetPEAdmConfig::NodeGroup do
    let(:data) do
      [
        { 'name' => 'PE Master', 'rule' => ['and'] },
        {
          'name' => 'PE Certificate Authority',
          'rule' => ['or', ['=', 'name', 'primary.example.com']],
          'config_data' => { 'foo' => { 'bar' => 'baz' } },
        },
      ]
    end
    subject(:node_group) { described_class.new(data) }

    describe '#dig' do
      # Catches a mutation that returns the first group (or raises) instead
      # of nil when no group matches the given name.
      it 'returns nil when no group matches the name' do
        expect(node_group.dig('Nonexistent Group')).to be_nil
      end

      # Catches a mutation that always drills into args even when none are
      # given, which would raise on Hash#dig() called with zero arguments.
      it 'returns the whole group hash when no further args are given' do
        expect(node_group.dig('PE Master')).to eq(data[0])
      end

      # Catches a mutation that indexes with [] instead of delegating to
      # Hash#dig(*args), losing multi-level lookups.
      it 'delegates to Hash#dig(*args) on the matched group when args are given' do
        expect(node_group.dig('PE Certificate Authority', 'config_data', 'foo', 'bar')).to eq('baz')
      end
    end

    describe '#pinned' do
      # Catches a mutation that raises instead of returning nil for a group
      # with no rule key at all (e.g. an unpinned or absent group).
      it 'returns nil when the named group has no rule key' do
        expect(node_group.pinned('PE Master with no rule')).to be_nil
      end

      # Catches a mutation that drops/inverts the rule.first == 'or' guard,
      # which would silently misinterpret an `and`-based rule as a pin.
      it 'raises when the rule is not an or-rule' do
        expect { node_group.pinned('PE Master') }.to raise_error('PE Master rule incompatible with pinning')
      end

      # Catches a mutation that filters on the wrong operator/field (e.g.
      # 'certname' instead of 'name', or '!=' instead of '=').
      it 'returns the single certname pinned via an or-rule = name clause' do
        expect(node_group.pinned('PE Certificate Authority')).to eq('primary.example.com')
      end

      # Catches a mutation that changes the <= 1 bound to allow multiple
      # pins through silently.
      it 'raises when more than one = name clause exists in the or-rule' do
        multi = [{
          'name' => 'PE Certificate Authority',
          'rule' => ['or', ['=', 'name', 'a.example.com'], ['=', 'name', 'b.example.com']],
        }]
        expect { described_class.new(multi).pinned('PE Certificate Authority') }
          .to raise_error('PE Certificate Authority contains more than one server!')
      end

      # Catches a mutation that broadens the select filter and counts a
      # non-name = clause as a pin, producing false positives/raises.
      it 'ignores non-name = clauses inside the same or-rule' do
        mixed = [{
          'name' => 'PE Certificate Authority',
          'rule' => ['or', ['=', 'name', 'a.example.com'], ['=', 'other_field', 'x']],
        }]
        expect(described_class.new(mixed).pinned('PE Certificate Authority')).to eq('a.example.com')
      end
    end
  end

  describe '#groups' do
    let(:https_dbl) { instance_double(Net::HTTP) }

    before(:each) do
      allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com',
                                                      hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                      hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
                                                      localcacert: '/etc/puppetlabs/puppet/ssl/certs/ca.pem')
      allow(File).to receive(:read).and_return('dummy-pem-contents')
      allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
      allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))
      allow(Net::HTTP).to receive(:new).with('primary.example.com', 4433).and_return(https_dbl)
      allow(https_dbl).to receive(:use_ssl=)
      allow(https_dbl).to receive(:cert=)
      allow(https_dbl).to receive(:key=)
      allow(https_dbl).to receive(:verify_mode=)
      allow(https_dbl).to receive(:ca_file=)
    end

    # Catches a mutation that drops the @groups ||= memoization, which would
    # cause a duplicate classifier round-trip on every subsequent call.
    it 'memoizes the classifier round-trip across repeated calls' do
      response = instance_double(Net::HTTPOK, body: [{ 'name' => 'PE Master' }].to_json)
      expect(https_dbl).to receive(:get).with('/classifier-api/v1/groups').once.and_return(response)

      task.groups
      task.groups
    end
  end

  describe '#pe_version' do
    # Catches a mutation that drops .strip, leaking a trailing newline into
    # the reported PE version.
    it 'returns the stripped file contents when /opt/puppetlabs/server/pe_build exists' do
      allow(File).to receive(:exist?).with('/opt/puppetlabs/server/pe_build').and_return(true)
      allow(File).to receive(:read).with('/opt/puppetlabs/server/pe_build').and_return("2023.8.9\n")

      expect(task.pe_version).to eq('2023.8.9')
    end

    # Catches a mutation that raises instead of returning nil on a
    # non-PE (or pre-pe_build-file) host.
    it 'returns nil when the pe_build file does not exist' do
      allow(File).to receive(:exist?).with('/opt/puppetlabs/server/pe_build').and_return(false)

      expect(task.pe_version).to be_nil
    end
  end

  describe '#server' do
    # Catches a mutation that drops the `return nil if certname_array.empty?`
    # short-circuit, which would send PuppetDB a syntactically invalid empty
    # `in []` clause.
    it 'returns nil without querying PuppetDB when certname_array is empty' do
      expect(task).not_to receive(:pdb_query)
      expect(task.server('puppet/server', 'A', [])).to be_nil
    end

    # Catches a mutation that swaps role/letter positions or drops one of
    # the two trusted.extensions clauses, misclassifying servers.
    it 'builds the PQL query embedding the given role and letter literally' do
      expect(task).to receive(:pdb_query)
        .with(a_string_including('"puppet/server"').and(a_string_including('"A"')).and(a_string_including('certname in ["primary.example.com"]')))
        .and_return([{ 'certname' => 'primary.example.com' }])

      expect(task.server('puppet/server', 'A', ['primary.example.com'])).to eq('primary.example.com')
    end

    # Catches a mutation that loosens server.size <= 1, letting an
    # ambiguous/duplicate classification through silently.
    it 'raises when PuppetDB returns more than one matching server' do
      allow(task).to receive(:pdb_query).and_return([{ 'certname' => 'a.example.com' }, { 'certname' => 'b.example.com' }])

      expect { task.server('puppet/server', 'A', ['a.example.com', 'b.example.com']) }
        .to raise_error('More than one A puppet/server server found!')
    end
  end

  describe '#compilers' do
    # Catches a mutation that reads the wrong OID or wrong trusted.extensions
    # key for the letter.
    it 'maps pe_compiler PuppetDB results into certname/letter pairs' do
      allow(task).to receive(:pdb_query)
        .with(a_string_matching(/pp_auth_role = "pe_compiler"/))
        .and_return([{ 'certname' => 'compiler-a.example.com', 'trusted.extensions' => { '1.3.6.1.4.1.34380.1.1.9813' => 'A' } }])

      expect(task.compilers).to eq([{ 'certname' => 'compiler-a.example.com', 'letter' => 'A' }])
    end
  end

  describe '#legacy_compilers' do
    # Catches a mutation that queries pe_compiler (non-legacy) instead of
    # pe_compiler_legacy, double-counting/misclassifying compilers. The
    # `.with` matcher below only accepts the pe_compiler_legacy filter text,
    # so a mutation swapping in the non-legacy filter fails this test.
    it 'maps pe_compiler_legacy PuppetDB results into certname/letter pairs' do
      allow(task).to receive(:pdb_query)
        .with(a_string_matching(/pp_auth_role = "pe_compiler_legacy"/))
        .and_return([{ 'certname' => 'legacy-a.example.com', 'trusted.extensions' => { '1.3.6.1.4.1.34380.1.1.9813' => 'B' } }])

      expect(task.legacy_compilers).to eq([{ 'certname' => 'legacy-a.example.com', 'letter' => 'B' }])
    end
  end

  describe '#execute!' do
    # Catches a mutation that always takes the error branch, hiding a
    # working config from convert-detection logic that depends on this
    # task's output.
    it 'prints config.to_json when a PE Primary A group exists' do
      allow(task).to receive(:groups).and_return(GetPEAdmConfig::NodeGroup.new([{ 'name' => 'PE Primary A' }]))
      allow(task).to receive(:config).and_return('foo' => 'bar')

      expect(STDOUT).to receive(:puts).with('{"foo":"bar"}')

      task.execute!
    end

    # PINS A REAL BUG (not fixed here, out of scope for this ticket):
    # `puts({...}).to_json` evaluates `puts({...})` first -- which prints
    # the Hash and returns nil -- and only THEN calls `.to_json` on that
    # nil return value, which is discarded. So this branch never actually
    # prints JSON at all; it prints the Hash's plain `to_s` output. A
    # consumer that tries to JSON-parse this task's stdout on a
    # non-peadm-cluster host would fail. This test pins that real, current
    # behavior (rather than the JSON output a naive reading of the code
    # would expect) so it still catches a mutation that inverts the
    # `if peadm_primary_a_group` check.
    it 'prints the raw error Hash (not JSON) when no PE Primary A group exists' do
      allow(task).to receive(:groups).and_return(GetPEAdmConfig::NodeGroup.new([]))

      expect(STDOUT).to receive(:puts).with({ 'error' => 'This is not a peadm-compatible cluster. Use peadm::convert first.' })

      task.execute!
    end
  end

  describe '#config' do
    let(:base_groups) do
      [
        { 'name' => 'PE Certificate Authority', 'rule' => ['or', ['=', 'name', 'primary.example.com']] },
        { 'name' => 'PE HA Replica', 'rule' => ['or', ['=', 'name', 'replica.example.com']] },
        {
          'name' => 'PE Primary A',
          'config_data' => { 'puppet_enterprise::profile::puppetdb' => { 'database_host' => 'primary.example.com' } },
        },
        { 'name' => 'PE Master', 'config_data' => { 'pe_repo' => { 'compile_master_pool_address' => 'pool.example.com' } } },
        {
          'name' => 'PE Compiler Group A',
          'classes' => { 'puppet_enterprise::profile::master' => { 'puppetdb_host' => ['x', 'compiler-pool-a.example.com'] } },
        },
        {
          'name' => 'PE Compiler Group B',
          'classes' => { 'puppet_enterprise::profile::master' => { 'puppetdb_host' => ['x', 'compiler-pool-b.example.com'] } },
        },
      ]
    end

    before(:each) do
      allow(task).to receive(:groups).and_return(GetPEAdmConfig::NodeGroup.new(base_groups))
      allow(task).to receive(:pe_version).and_return('2023.8.9')
      allow(task).to receive(:compilers).and_return([{ 'certname' => 'compiler-a.example.com', 'letter' => 'A' },
                                                       { 'certname' => 'compiler-b.example.com', 'letter' => 'B' }])
      allow(task).to receive(:legacy_compilers).and_return([])
    end

    # Catches a mutation that hardcodes 'A' or inverts the ternary, which
    # would silently swap which PostgreSQL host is reported as primary vs
    # replica when the primary node is actually server_a.
    it 'derives primary_letter A when the pinned primary matches server_a' do
      allow(task).to receive(:server).with('puppet/server', 'A', ['primary.example.com', 'replica.example.com']).and_return('primary.example.com')
      allow(task).to receive(:server).with('puppet/server', 'B', ['primary.example.com', 'replica.example.com']).and_return('replica.example.com')
      allow(task).to receive(:server).with('puppet/puppetdb-database', 'A', ['primary.example.com']).and_return('pgsql-a.example.com')
      allow(task).to receive(:server).with('puppet/puppetdb-database', 'B', ['primary.example.com']).and_return('pgsql-b.example.com')

      config = task.config
      expect(config['role-letter']['server']).to eq('A' => 'primary.example.com', 'B' => 'replica.example.com')
      expect(config['params']['primary_host']).to eq('primary.example.com')
      expect(config['params']['primary_postgresql_host']).to eq('pgsql-a.example.com')
    end

    # Same derivation, but with server_a/server_b swapped relative to which
    # node is actually pinned as primary -- catches a mutation that always
    # reports 'A' (or otherwise ignores which server the primary really is).
    it 'derives primary_letter B when the pinned primary matches server_b instead' do
      allow(task).to receive(:server).with('puppet/server', 'A', ['primary.example.com', 'replica.example.com']).and_return('replica.example.com')
      allow(task).to receive(:server).with('puppet/server', 'B', ['primary.example.com', 'replica.example.com']).and_return('primary.example.com')
      allow(task).to receive(:server).with('puppet/puppetdb-database', 'A', ['primary.example.com']).and_return('pgsql-a.example.com')
      allow(task).to receive(:server).with('puppet/puppetdb-database', 'B', ['primary.example.com']).and_return('pgsql-b.example.com')

      config = task.config
      expect(config['role-letter']['server']).to eq('A' => 'replica.example.com', 'B' => 'primary.example.com')
      # primary_letter is now 'B', so primary_postgresql_host must follow
      # postgresql['B'], not postgresql['A'] -- this is the assertion a
      # hardcoded/inverted ternary mutation would fail.
      expect(config['params']['primary_postgresql_host']).to eq('pgsql-b.example.com')
      expect(config['params']['replica_postgresql_host']).to eq('pgsql-a.example.com')
    end

    # Catches a mutation that uses legacy_compilers in the compilers slot
    # (or vice versa) -- an easy copy-paste bug given the parallel
    # structure -- or that drops the .select filter and assigns everything
    # to one letter.
    it 'partitions compilers (not legacy_compilers) by letter under role-letter.compilers' do
      allow(task).to receive(:server).and_return(nil)

      config = task.config
      expect(config['role-letter']['compilers']).to eq('A' => ['compiler-a.example.com'], 'B' => ['compiler-b.example.com'])
      expect(config['role-letter']['legacy_compilers']).to eq('A' => [], 'B' => [])
    end

    # Catches a mutation that drops .compact, which would pass a PQL
    # `certname in [..., null, ...]` array that PuppetDB would reject --
    # here only PE Primary A has a configured database_host, so PE Primary
    # B's missing entry must be filtered out, not passed through as nil.
    it 'compacts a nil database_host when only one Primary group has config_data' do
      expect(task).to receive(:server).with('puppet/puppetdb-database', 'A', ['primary.example.com']).and_return('pgsql-a.example.com')
      expect(task).to receive(:server).with('puppet/puppetdb-database', 'B', ['primary.example.com']).and_return(nil)
      allow(task).to receive(:server).with('puppet/server', anything, anything).and_return(nil)

      task.config
    end
  end
end
