require 'spec_helper'
require_relative '../../../tasks/check_pe_master_rules'

describe CheckPeMasterRules do
  # NOTE: initialize(params) stores @params, but no method in this class
  # ever reads it -- unused, dead state. Not a bug worth fixing here, just
  # flagging for anyone reading this spec.
  subject(:task) { described_class.new({}) }

  let(:https_dbl) { instance_double(Net::HTTP) }

  before(:each) do
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com',
                                                    hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                    hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
                                                    localcacert: '/etc/puppetlabs/puppet/ssl/certs/ca.pem')
    allow(File).to receive(:read).and_return('dummy-pem-contents')
    allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))
    allow(https_dbl).to receive(:use_ssl=)
    allow(https_dbl).to receive(:cert=)
    allow(https_dbl).to receive(:key=)
    allow(https_dbl).to receive(:verify_mode=)
    allow(https_dbl).to receive(:ca_file=)
  end

  describe '#check_rules_updated' do
    # Catches a mutation that drops the `return false unless rules.is_a?(Array)`
    # type guard.
    it 'returns false when rules is not an Array' do
      expect(task.check_rules_updated(nil)).to eq(false)
      expect(task.check_rules_updated('rule' => [])).to eq(false)
    end

    # Catches a mutation that changes the `> 1` bound to `>= 1` or `> 0`,
    # which would try to index rules[1] on a too-short array.
    it 'returns false when rules has one or zero elements' do
      expect(task.check_rules_updated([])).to eq(false)
      expect(task.check_rules_updated(['and'])).to eq(false)
    end

    # Catches a mutation that drops either half of the
    # rules[1].is_a?(Array) && rules[1][0] == 'or' compound condition.
    it 'returns false when rules[1] is not an or-array' do
      expect(task.check_rules_updated(['and', 'not-an-array'])).to eq(false)
      expect(task.check_rules_updated(['and', ['and', 'nested']])).to eq(false)
    end

    or_clause = ->(role) { ['=', ['trusted', 'extensions', 'pp_auth_role'], role] }

    # Target "already updated" shape: both pe_compiler and
    # pe_compiler_legacy present in the or-rule.
    it 'returns true when both pe_compiler and pe_compiler_legacy clauses are present' do
      rules = ['and', ['or', or_clause.call('pe_compiler'), or_clause.call('pe_compiler_legacy')]]
      expect(task.check_rules_updated(rules)).to eq(true)
    end

    # Catches a mutation that changes && to || in
    # pe_compiler_found && pe_compiler_legacy_found, which would report
    # "updated" prematurely.
    it 'returns false when only pe_compiler is present (legacy not yet added)' do
      rules = ['and', ['or', or_clause.call('pe_compiler')]]
      expect(task.check_rules_updated(rules)).to eq(false)
    end

    it 'returns false when only pe_compiler_legacy is present' do
      rules = ['and', ['or', or_clause.call('pe_compiler_legacy')]]
      expect(task.check_rules_updated(rules)).to eq(false)
    end

    # Catches a mutation that drops the rule[1] == [...] field-path check
    # and matches on operator/value alone, producing false positives from
    # unrelated rules that happen to end in the right value.
    it 'ignores a clause targeting a different fact even with a matching value' do
      unrelated = ['=', ['trusted', 'extensions', 'some_other_fact'], 'pe_compiler_legacy']
      rules = ['and', ['or', or_clause.call('pe_compiler'), unrelated]]
      expect(task.check_rules_updated(rules)).to eq(false)
    end

    # Catches a mutation that drops the rule[0] == '=' operator check.
    it 'ignores a non-= operator clause with the right field/value' do
      not_equal = ['!=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy']
      rules = ['and', ['or', or_clause.call('pe_compiler'), not_equal]]
      expect(task.check_rules_updated(rules)).to eq(false)
    end
  end

  describe '#get_pe_master_group_id' do
    before(:each) do
      allow(Net::HTTP).to receive(:new).with('primary.example.com', 4433).and_return(https_dbl)
    end

    # Catches a mutation that drops/inverts the res.code == '200' guard.
    # NOTE: the inner `raise "Failed to fetch groups: HTTP ..."` is a plain
    # RuntimeError (not a JSON::ParserError), so it matches this method's
    # `rescue StandardError` clause, which wraps it with its own
    # "Error fetching PE Master group ID: " prefix -- the final message
    # below has both prefixes concatenated, not just the plain inner one.
    it 'raises a doubly-wrapped error when the classifier responds non-200' do
      response = instance_double(Net::HTTPUnauthorized, code: '401', body: 'unauthorized')
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

      expect { task.get_pe_master_group_id }.to raise_error(
        'Error fetching PE Master group ID: Failed to fetch groups: HTTP 401 - unauthorized',
      )
    end

    # Catches a mutation that returns nil/the wrong id instead of raising
    # when the 200 response body has no 'PE Master'-named group.
    it 'raises a doubly-wrapped error when no PE Master group is present in a 200 response' do
      response = instance_double(Net::HTTPOK, code: '200', body: [{ 'name' => 'PE Other' }].to_json)
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

      expect { task.get_pe_master_group_id }.to raise_error(
        'Error fetching PE Master group ID: Could not find PE Master group',
      )
    end

    # Happy path.
    it 'returns the PE Master group id on success' do
      response = instance_double(Net::HTTPOK, code: '200', body: [{ 'name' => 'PE Master', 'id' => 'group-id-123' }].to_json)
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

      expect(task.get_pe_master_group_id).to eq('group-id-123')
    end

    # Catches a mutation that collapses the two rescue clauses into one,
    # losing the more specific JSON diagnostic.
    it 'wraps a JSON::ParserError from a malformed 200 response distinctly from other errors' do
      response = instance_double(Net::HTTPOK, code: '200', body: 'not json')
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

      expect { task.get_pe_master_group_id }.to raise_error(a_string_matching(%r{\AInvalid JSON response from server: }))
    end
  end

  describe '#get_current_rules' do
    let(:request_dbl) { instance_double(Net::HTTP::Get) }

    before(:each) do
      allow(Net::HTTP).to receive(:new).with('primary.example.com', 4433).and_return(https_dbl)
      allow(Net::HTTP::Get).to receive(:new).with('/classifier-api/v1/groups/group-id-123/rules').and_return(request_dbl)
    end

    # Catches a mutation that returns the whole parsed body instead of just
    # its 'rule' key.
    it 'returns only the rule key from a 200 response, not the whole parsed body' do
      response = instance_double(Net::HTTPOK, code: '200', body: { 'rule' => ['and'], 'other' => 'field' }.to_json)
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)

      expect(task.get_current_rules('group-id-123')).to eq(['and'])
    end

    # Same doubly-wrapped-rescue shape as #get_pe_master_group_id.
    it 'raises a doubly-wrapped error on a non-200 response' do
      response = instance_double(Net::HTTPNotFound, code: '404', body: 'not found')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)

      expect { task.get_current_rules('group-id-123') }.to raise_error(
        'Error fetching rules: Failed to fetch rules: HTTP 404 - not found',
      )
    end

    it 'wraps a JSON::ParserError from a malformed 200 response distinctly from other errors' do
      response = instance_double(Net::HTTPOK, code: '200', body: 'not json')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)

      expect { task.get_current_rules('group-id-123') }.to raise_error(a_string_matching(%r{\AInvalid JSON response from server: }))
    end
  end

  describe '#check_nodes_with_legacy_compiler_oid' do
    let(:pdb_request_dbl) { instance_double(Net::HTTP::Get) }

    before(:each) do
      allow(Net::HTTP).to receive(:new).with('primary.example.com', 8081).and_return(https_dbl)
      allow(Net::HTTP::Get).to receive(:new).with('/pdb/query/v4').and_return(pdb_request_dbl)
      allow(pdb_request_dbl).to receive(:set_form_data)
    end

    # Catches a mutation that inverts !nodes.empty?
    it 'reports nodes_found false with an empty list when PuppetDB returns no matches' do
      response = instance_double(Net::HTTPOK, code: '200', body: [].to_json)
      allow(https_dbl).to receive(:request).with(pdb_request_dbl).and_return(response)

      expect(task.check_nodes_with_legacy_compiler_oid).to eq('nodes_found' => false, 'count' => 0, 'nodes' => [])
    end

    # Catches a mutation that returns raw node hashes instead of mapping
    # down to just each node's certname.
    it 'maps PuppetDB rows down to certnames when matches are found' do
      response = instance_double(Net::HTTPOK, code: '200',
                                                body: [{ 'certname' => 'legacy-a.example.com', 'trusted.extensions' => {} }].to_json)
      allow(https_dbl).to receive(:request).with(pdb_request_dbl).and_return(response)

      expect(task.check_nodes_with_legacy_compiler_oid).to eq('nodes_found' => true, 'count' => 1, 'nodes' => ['legacy-a.example.com'])
    end

    it 'raises a doubly-wrapped error on a non-200 PuppetDB response' do
      response = instance_double(Net::HTTPInternalServerError, code: '500', body: 'boom')
      allow(https_dbl).to receive(:request).with(pdb_request_dbl).and_return(response)

      expect { task.check_nodes_with_legacy_compiler_oid }.to raise_error(
        'Error checking for legacy compiler OID: Failed to query PuppetDB: HTTP 500 - boom',
      )
    end

    it 'wraps a JSON::ParserError from a malformed 200 response distinctly from other errors' do
      response = instance_double(Net::HTTPOK, code: '200', body: 'not json')
      allow(https_dbl).to receive(:request).with(pdb_request_dbl).and_return(response)

      expect { task.check_nodes_with_legacy_compiler_oid }.to raise_error(a_string_matching(%r{\AInvalid JSON response from PuppetDB: }))
    end
  end

  describe '#execute!' do
    before(:each) do
      allow(STDOUT).to receive(:puts)
      allow(task).to receive(:get_pe_master_group_id).and_return('group-id-123')
      allow(task).to receive(:get_current_rules).and_return([])
    end

    # Catches a mutation that checks legacy_compiler_nodes before
    # rules_updated, which would produce the wrong message for this
    # combination.
    it 'reports not-updated when rules_updated is false, regardless of nodes_found' do
      allow(task).to receive(:check_rules_updated).and_return(false)
      allow(task).to receive(:check_nodes_with_legacy_compiler_oid).and_return('nodes_found' => true, 'count' => 1, 'nodes' => ['x'])

      expect(STDOUT).to receive(:puts) do |json_str|
        parsed = JSON.parse(json_str)
        expect(parsed['updated']).to eq(false)
        expect(parsed['message']).to eq('PE Master rules need to be updated to support pe_compiler_legacy')
      end

      task.execute!
    end

    # Catches a mutation that drops the !legacy_compiler_nodes['nodes_found']
    # half of the is_updated compound, which would report updated: true
    # while nodes with the legacy OID still exist.
    it 'reports updated-but-legacy-nodes-remain when rules are updated but nodes_found is true' do
      allow(task).to receive(:check_rules_updated).and_return(true)
      allow(task).to receive(:check_nodes_with_legacy_compiler_oid).and_return('nodes_found' => true, 'count' => 1, 'nodes' => ['x'])

      expect(STDOUT).to receive(:puts) do |json_str|
        parsed = JSON.parse(json_str)
        expect(parsed['updated']).to eq(false)
        expect(parsed['message']).to eq('PE Master rules are updated, but nodes with legacy compiler OID still exist')
      end

      task.execute!
    end

    # Only the fully-updated combination reports updated: true.
    it 'reports fully-updated only when rules_updated is true and nodes_found is false' do
      allow(task).to receive(:check_rules_updated).and_return(true)
      allow(task).to receive(:check_nodes_with_legacy_compiler_oid).and_return('nodes_found' => false, 'count' => 0, 'nodes' => [])

      expect(STDOUT).to receive(:puts) do |json_str|
        parsed = JSON.parse(json_str)
        expect(parsed['updated']).to eq(true)
        expect(parsed['message']).to eq('PE Master rules have been updated with pe_compiler_legacy support and no legacy compiler OIDs found')
      end

      task.execute!
    end

    # Catches a mutation that drops the top-level rescue/exit 1, letting an
    # unhandled group-lookup failure crash the task instead of reporting a
    # clean error.
    it 'catches an upstream StandardError, prints a clean error, and exits 1' do
      allow(task).to receive(:get_pe_master_group_id).and_raise(StandardError, 'Error fetching PE Master group ID: boom')

      expect(STDOUT).to receive(:puts).with('{"error":"Error fetching PE Master group ID: boom","updated":false}')
      expect { task.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end
end
