require 'spec_helper'
require_relative '../../../tasks/node_group_unpin'

describe NodeGroupUnpin do
  let(:valid_params) { { 'node_certnames' => ['node1.example.com'], 'group_name' => 'My Group' } }
  let(:https_dbl) { instance_double(Net::HTTP) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(YAML).to receive(:load_file).with('/etc/puppetlabs/puppet/classifier.yaml').and_return('token' => 'abc')
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

  describe '#initialize' do
    # Catches a mutation that drops the node_certnames presence check.
    it "raises when 'node_certnames' is missing" do
      expect { described_class.new('group_name' => 'My Group') }.to raise_error("Missing required parameter 'node_certnames'")
    end

    # Catches a mutation that drops the Array type check, allowing e.g. a
    # bare String to be iterated character-by-character downstream.
    it "raises when 'node_certnames' is not an array" do
      params = { 'node_certnames' => 'node1.example.com', 'group_name' => 'My Group' }

      expect { described_class.new(params) }.to raise_error("'node_certnames' must be an array")
    end

    # Catches a mutation that drops the group_name presence check.
    it "raises when 'group_name' is missing" do
      params = { 'node_certnames' => ['node1.example.com'] }

      expect { described_class.new(params) }.to raise_error("Missing required parameter 'group_name'")
    end

    # Catches a mutation that lets the raw Errno::ENOENT propagate instead
    # of a targeted, actionable message.
    it 'raises a targeted error when classifier.yaml is missing' do
      allow(YAML).to receive(:load_file).with('/etc/puppetlabs/puppet/classifier.yaml').and_raise(Errno::ENOENT)

      expect { described_class.new(valid_params) }.to raise_error('Could not find classifier.yaml at /etc/puppetlabs/puppet/classifier.yaml')
    end

    # Catches a mutation that skips loading the classifier auth file
    # entirely during construction (the three param-validation orderings
    # are already distinguished by the preceding tests, each of which
    # supplies exactly one invalid param).
    it 'loads the classifier auth file during construction' do
      expect(YAML).to receive(:load_file).with('/etc/puppetlabs/puppet/classifier.yaml').and_return('token' => 'abc')

      described_class.new(valid_params)
    end
  end

  describe '#groups' do
    subject(:task) { described_class.new(valid_params) }

    # Catches a mutation that returns the raw parsed Array instead of
    # wrapping it in a NodeGroup for #dig to work against.
    it 'returns a NodeGroup wrapping the parsed groups response' do
      response = instance_double(Net::HTTPOK, code: '200', body: [{ 'name' => 'My Group', 'id' => 'g1' }].to_json)
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

      expect(task.groups.data).to eq([{ 'name' => 'My Group', 'id' => 'g1' }])
    end

    # Catches a mutation that drops the ||= memoization and re-fetches on
    # every call.
    it 'memoizes the groups fetch across multiple calls' do
      response = instance_double(Net::HTTPOK, code: '200', body: '[]')
      expect(https_dbl).to receive(:get).with('/classifier-api/v1/groups').once.and_return(response)

      task.groups
      task.groups
    end

    # Catches a mutation that drops the HTTP status check.
    it 'raises a targeted error when the fetch returns a non-200 status' do
      response = instance_double(Net::HTTPServerError, code: '500', body: 'boom')
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

      expect { task.groups }.to raise_error(%r{Failed to fetch groups: HTTP 500 - boom})
    end

    # Catches a mutation that lets a JSON::ParserError propagate raw.
    it 'wraps a malformed JSON response with a targeted error' do
      response = instance_double(Net::HTTPOK, code: '200', body: 'not json')
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

      expect { task.groups }.to raise_error(%r{Invalid JSON response from server})
    end

    # Catches a mutation that lets an unrelated StandardError propagate
    # raw instead of wrapping it.
    it 'wraps any other StandardError with a targeted error' do
      allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_raise(StandardError, 'connection reset')

      expect { task.groups }.to raise_error(%r{Error fetching groups: connection reset})
    end
  end

  describe '#unpin_node' do
    subject(:task) { described_class.new(valid_params) }

    let(:request_dbl) { instance_double(Net::HTTP::Post) }
    let(:group) { { 'id' => 'g1', 'name' => 'My Group' } }

    before(:each) do
      allow(Net::HTTP::Post).to receive(:new).with('/classifier-api/v1/groups/g1/unpin').and_return(request_dbl)
      allow(request_dbl).to receive(:[]=)
      allow(request_dbl).to receive(:body=)
    end

    # Catches a mutation that drops the group shape validation and
    # proceeds to use a malformed group's missing id/name. This guard
    # runs before the method's own begin/rescue, so it raises unwrapped.
    it 'raises when given an invalid group object' do
      expect { task.unpin_node({ 'name' => 'My Group' }, ['node1']) }.to raise_error('Invalid group object')
      expect { task.unpin_node({ 'id' => 'g1' }, ['node1']) }.to raise_error('Invalid group object')
      expect { task.unpin_node('not-a-hash', ['node1']) }.to raise_error('Invalid group object')
    end

    # Catches a mutation that posts to the wrong URL, drops the
    # content-type header, or sends the wrong node list shape.
    it 'posts the node list to the unpin endpoint with a JSON content-type' do
      success_response = instance_double(Net::HTTPNoContent, code: '204')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(success_response)
      expect(request_dbl).to receive(:[]=).with('Content-Type', 'application/json')
      expect(request_dbl).to receive(:body=).with({ nodes: ['node1.example.com'] }.to_json)

      task.unpin_node(group, ['node1.example.com'])
    end

    # Catches a mutation that prints the wrong node list or group name.
    it 'prints a success message naming the unpinned nodes and group on 204' do
      success_response = instance_double(Net::HTTPNoContent, code: '204')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(success_response)

      expect(STDOUT).to receive(:puts).with("Successfully unpinned nodes 'node1.example.com' from group 'My Group'")

      task.unpin_node(group, ['node1.example.com'])
    end

    # Catches a mutation that drops the parsed-error-body branch.
    it "raises using the server's error kind when unpin fails with a parseable JSON error body" do
      error_response = instance_double(Net::HTTPServerError, code: '422', body: { 'kind' => 'validation-error' }.to_json)
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(error_response)

      expect { task.unpin_node(group, ['node1.example.com']) }.to raise_error(%r{Error during unpin request: Failed to unpin nodes: validation-error})
    end

    # Catches a mutation that assumes every non-204 body is JSON.
    it 'raises a generic invalid-response error when the error body is not JSON' do
      error_response = instance_double(Net::HTTPServerError, code: '500', body: 'internal server error')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(error_response)

      expect { task.unpin_node(group, ['node1.example.com']) }.to raise_error(%r{Error during unpin request: Invalid response from server \(status 500\): internal server error})
    end
  end

  describe NodeGroupUnpin::NodeGroup do
    subject(:node_group) { described_class.new(data) }

    let(:data) { [{ 'name' => 'My Group', 'id' => 'g1', 'nested' => { 'key' => 'value' } }] }

    # Catches a mutation that raises or returns the wrong sentinel instead
    # of nil for an absent group name.
    it 'returns nil when no group with the given name exists' do
      expect(node_group.dig('Missing Group')).to be_nil
    end

    # Catches a mutation that always digs further even when no extra args
    # are given, instead of returning the whole group hash.
    it 'returns the full group hash when found with no further args' do
      expect(node_group.dig('My Group')).to eq(data.first)
    end

    # Catches a mutation that ignores extra args instead of delegating to
    # the found group hash's own #dig.
    it "delegates to the found group's own #dig when further args are given" do
      expect(node_group.dig('My Group', 'nested', 'key')).to eq('value')
    end
  end

  describe '#execute!' do
    let(:task) { described_class.new(valid_params) }

    # Catches a mutation that unpins from the wrong group, skips the
    # found-group check, or prints the wrong confirmation message.
    it 'unpins the nodes and prints a confirmation when the group is found' do
      group = { 'id' => 'g1', 'name' => 'My Group' }
      allow(task).to receive(:groups).and_return(instance_double(NodeGroupUnpin::NodeGroup, dig: group))
      expect(task).to receive(:unpin_node).with(group, ['node1.example.com'])
      expect(STDOUT).to receive(:puts).with('Unpinned node1.example.com from My Group')

      task.execute!
    end

    # Catches a mutation that calls unpin_node even when the group isn't
    # found, instead of reporting it missing. Pins existing (not newly
    # introduced) behavior rather than endorsing it: a not-found group is
    # treated as a non-error -- execute! exits 0 having done nothing,
    # rather than failing the task -- unchanged by this ticket's scope.
    it 'reports the group as not found and skips unpinning when absent' do
      allow(task).to receive(:groups).and_return(instance_double(NodeGroupUnpin::NodeGroup, dig: nil))
      expect(task).not_to receive(:unpin_node)
      expect(STDOUT).to receive(:puts).with('Group My Group not found')

      task.execute!
    end
  end
end
