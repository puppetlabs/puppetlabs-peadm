require 'spec_helper'
require_relative '../../../tasks/update_pe_master_rules'

describe UpdatePeMasterRules do
  subject(:task) { described_class.new({}) }

  let(:https_dbl) { instance_double(Net::HTTP) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
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

  describe '#get_pe_master_group_id' do
    # Catches a mutation that searches for the wrong group name or returns
    # a different group's id.
    it "returns the id of the group named 'PE Master'" do
      groups_response = instance_double(Net::HTTPOK, code: '200',
                                                       body: [{ 'name' => 'PE Master', 'id' => 'master-id' },
                                                              { 'name' => 'Other', 'id' => 'other-id' }].to_json)
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      expect(task.get_pe_master_group_id).to eq('master-id')
    end

    # Catches a mutation that drops the HTTP status check and proceeds to
    # parse an error response as if it were valid group data.
    it 'raises a targeted error when the groups fetch returns a non-200 status' do
      error_response = instance_double(Net::HTTPServerError, code: '500', body: 'boom')
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(error_response)

      expect { task.get_pe_master_group_id }.to raise_error(%r{Failed to fetch groups: HTTP 500 - boom})
    end

    # Catches a mutation that drops the "group not found" guard and
    # instead raises a NoMethodError on nil. The method's own blanket
    # StandardError rescue re-wraps this raise with its generic prefix,
    # same as any other StandardError raised inside the method.
    it "raises a targeted error when no group named 'PE Master' exists" do
      groups_response = instance_double(Net::HTTPOK, code: '200', body: [{ 'name' => 'Other', 'id' => 'other-id' }].to_json)
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(groups_response)

      expect { task.get_pe_master_group_id }.to raise_error('Error fetching PE Master group ID: Could not find PE Master group')
    end

    # Catches a mutation that lets a JSON::ParserError propagate raw
    # instead of wrapping it with a targeted message.
    it 'wraps a malformed JSON response with a targeted error' do
      bad_response = instance_double(Net::HTTPOK, code: '200', body: 'not json')
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(bad_response)

      expect { task.get_pe_master_group_id }.to raise_error(%r{Invalid JSON response from server})
    end

    # Catches a mutation that lets an unrelated StandardError (e.g. a
    # network failure) propagate raw instead of wrapping it.
    it 'wraps any other StandardError with a targeted error' do
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_raise(StandardError, 'connection reset')

      expect { task.get_pe_master_group_id }.to raise_error(%r{Error fetching PE Master group ID: connection reset})
    end
  end

  describe '#get_current_rules' do
    let(:request_dbl) { instance_double(Net::HTTP::Get) }

    before(:each) do
      allow(Net::HTTP::Get).to receive(:new).with('/classifier-api/v1/groups/group-1/rules').and_return(request_dbl)
    end

    # Catches a mutation that fetches the wrong group's rules, or returns
    # the whole parsed body instead of just the 'rule' key.
    it 'returns the rule array for the given group_id' do
      rules_response = instance_double(Net::HTTPOK, code: '200', body: { 'rule' => ['and', ['=', 'foo', 'bar']] }.to_json)
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(rules_response)

      expect(task.get_current_rules('group-1')).to eq(['and', ['=', 'foo', 'bar']])
    end

    # Catches a mutation that drops the HTTP status check.
    it 'raises a targeted error when the rules fetch returns a non-200 status' do
      error_response = instance_double(Net::HTTPServerError, code: '404', body: 'not found')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(error_response)

      expect { task.get_current_rules('group-1') }.to raise_error(%r{Failed to fetch rules: HTTP 404 - not found})
    end

    # Catches a mutation that lets a JSON::ParserError propagate raw.
    it 'wraps a malformed JSON response with a targeted error' do
      bad_response = instance_double(Net::HTTPOK, code: '200', body: 'not json')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(bad_response)

      expect { task.get_current_rules('group-1') }.to raise_error(%r{Invalid JSON response from server})
    end

    # Catches a mutation that lets an unrelated StandardError propagate raw.
    it 'wraps any other StandardError with a targeted error' do
      allow(https_dbl).to receive(:request).with(request_dbl).and_raise(StandardError, 'timeout')

      expect { task.get_current_rules('group-1') }.to raise_error(%r{Error fetching rules: timeout})
    end
  end

  describe '#modify_pe_master_rules' do
    # Catches a mutation that tries to index into a non-Array ruleset
    # instead of returning it unchanged.
    it 'returns non-Array rules unchanged' do
      expect(task.modify_pe_master_rules(nil)).to be_nil
      expect(task.modify_pe_master_rules('not-an-array')).to eq('not-an-array')
    end

    # Catches a mutation that drops one of the two role clauses, uses the
    # wrong operator, or replaces the wrong index -- and confirms sibling
    # elements outside index 1 are preserved untouched.
    it 'replaces index 1 with an or clause matching pe_compiler and pe_compiler_legacy, preserving other elements' do
      original = ['and', ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'], ['=', 'other', 'clause']]

      result = task.modify_pe_master_rules(original)

      expect(result).to eq([
                             'and',
                             ['or',
                              ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler'],
                              ['=', ['trusted', 'extensions', 'pp_auth_role'], 'pe_compiler_legacy']],
                             ['=', 'other', 'clause'],
                           ])
    end

    # Catches a mutation that modifies the input array in place instead of
    # operating on a copy.
    it 'does not mutate the original rules array' do
      original = ['and', ['=', 'x', 'y'], ['=', 'other', 'clause']]
      original_dup = original.dup

      task.modify_pe_master_rules(original)

      expect(original).to eq(original_dup)
    end
  end

  describe '#update_rules' do
    let(:rules_request_dbl) { instance_double(Net::HTTP::Get) }
    let(:update_request_dbl) { instance_double(Net::HTTP::Post) }

    before(:each) do
      allow(Net::HTTP::Get).to receive(:new).with('/classifier-api/v1/groups/group-1/rules').and_return(rules_request_dbl)
      rules_response = instance_double(Net::HTTPOK, code: '200', body: { 'rule' => ['and'] }.to_json)
      allow(https_dbl).to receive(:request).with(rules_request_dbl).and_return(rules_response)

      allow(Net::HTTP::Post).to receive(:new).with('/classifier-api/v1/groups/group-1').and_return(update_request_dbl)
      allow(update_request_dbl).to receive(:[]=)
      allow(update_request_dbl).to receive(:body=)
    end

    # Catches a mutation that posts to the wrong URL, drops the
    # content-type header, or sends a differently-shaped body.
    it 'posts the modified rules to the group with a JSON content-type' do
      expected_rules = task.modify_pe_master_rules(['and'])
      success_response = instance_double(Net::HTTPOK, code: '200')
      allow(https_dbl).to receive(:request).with(update_request_dbl).and_return(success_response)
      expect(update_request_dbl).to receive(:[]=).with('Content-Type', 'application/json')
      expect(update_request_dbl).to receive(:body=).with({ rule: expected_rules }.to_json)

      task.update_rules('group-1')
    end

    # Catches a mutation that drops one of the three accepted success
    # codes, or prints the wrong message/group_id. Pins the exact,
    # pre-existing message text as-is, including its "regex match"
    # wording -- the actual logic is exact `=` equality against two
    # literal values, not a regex match (see modify_pe_master_rules
    # above); this is a known, pre-existing inaccuracy in a user-facing
    # log line, unchanged by this ticket's structural-only comment fix.
    ['200', '201', '204'].each do |code|
      it "prints a success message naming the group when the update responds #{code}" do
        success_response = instance_double(Net::HTTPOK, code: code)
        allow(https_dbl).to receive(:request).with(update_request_dbl).and_return(success_response)

        expect(STDOUT).to receive(:puts).with(
          'Successfully transformed pe_compiler rule to use regex match for *_compiler roles in group group-1',
        )

        task.update_rules('group-1')
      end
    end

    # Catches a mutation that drops the parsed-error-body branch and
    # always raises the generic "invalid response" message instead.
    it "raises using the server's error kind when the update fails with a parseable JSON error body" do
      error_response = instance_double(Net::HTTPServerError, code: '422', body: { 'kind' => 'validation-error' }.to_json)
      allow(https_dbl).to receive(:request).with(update_request_dbl).and_return(error_response)

      expect { task.update_rules('group-1') }.to raise_error(%r{Error during rules update: Failed to update rules: validation-error})
    end

    # Catches a mutation that assumes every non-success body is JSON and
    # raises a JSON::ParserError instead of the intended fallback message.
    it 'raises a generic invalid-response error when the error body is not JSON' do
      error_response = instance_double(Net::HTTPServerError, code: '500', body: 'internal server error')
      allow(https_dbl).to receive(:request).with(update_request_dbl).and_return(error_response)

      expect { task.update_rules('group-1') }.to raise_error(%r{Error during rules update: Invalid response from server \(status 500\): internal server error})
    end

    # Catches a mutation that drops update_rules's own rescue, which wraps
    # even upstream failures (like get_current_rules's own targeted error)
    # with an additional "Error during rules update" prefix.
    it "wraps a failure from fetching the current rules with update_rules's own error prefix" do
      allow(https_dbl).to receive(:request).with(rules_request_dbl).and_raise(StandardError, 'network down')

      expect { task.update_rules('group-1') }.to raise_error(%r{Error during rules update: Error fetching rules: network down})
    end
  end

  describe '#execute!' do
    let(:task) { described_class.new({}) }

    # Catches a mutation that skips fetching the group id, hardcodes a
    # different id, or fails to forward it into update_rules.
    it 'fetches the PE Master group id and updates rules for that group' do
      allow(task).to receive(:get_pe_master_group_id).and_return('found-group-id')
      expect(task).to receive(:update_rules).with('found-group-id')

      task.execute!
    end
  end
end
