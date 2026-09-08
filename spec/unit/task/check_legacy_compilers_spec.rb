require 'spec_helper'
require_relative '../../../tasks/check_legacy_compilers'

describe CheckLegacyCompilers do
  describe '#initialize' do
    # PINS A REAL BUG (not fixed here, out of scope for this ticket): there
    # is no `else` branch, so @nodes is left nil for any non-String (or
    # missing) legacy_compilers param, and execute!'s first line is
    # `@nodes.each`, which raises NoMethodError on nil. The one production
    # call site (plans/convert.pp:376) is guarded by `if $legacy_compilers`
    # and always passes a String (`.join(',')`), so this path is dead in
    # practice -- but the code itself is directly reachable and this is a
    # real defect, not something this ticket fixes.
    it 'raises NoMethodError from execute! when legacy_compilers is not a String' do
      task = described_class.new('legacy_compilers' => nil)
      expect { task.execute! }.to raise_error(NoMethodError)
    end

    # Catches a mutation that uses the wrong delimiter or drops .split
    # entirely.
    it 'splits a comma-separated legacy_compilers string into individual node names' do
      task = described_class.new('legacy_compilers' => 'a.example.com,b.example.com')

      expect(task).to receive(:get_node_classification).with('a.example.com').and_return('groups' => [])
      expect(task).to receive(:get_node_classification).with('b.example.com').and_return('groups' => [])

      task.execute!
    end
  end

  describe '#execute!' do
    subject(:task) { described_class.new('legacy_compilers' => 'legacy-a.example.com') }

    before(:each) { allow(STDOUT).to receive(:puts) }

    # Catches a mutation that compares against the wrong group name.
    it 'pins a node whose classification includes a group named exactly "PE Master"' do
      allow(task).to receive(:get_node_classification).and_return('groups' => [{ 'name' => 'PE Master' }])

      expect(STDOUT).to receive(:puts).with('legacy-a.example.com')
      task.execute!
    end

    # Catches a mutation that drops this whole parameters/pe_master branch,
    # missing a real (if less common) pinning mechanism.
    it 'pins a node with no PE Master group but a truthy parameters.pe_master value' do
      allow(task).to receive(:get_node_classification)
        .and_return('groups' => [], 'parameters' => { 'pe_master' => true })

      expect(STDOUT).to receive(:puts).with('legacy-a.example.com')
      task.execute!
    end

    # Catches a mutation that drops the `next unless
    # node_classification.key?('parameters')` guard, which would otherwise
    # raise (calling .key? on a missing hash) instead of skipping cleanly.
    it 'does not pin (and does not raise on) a node whose classification has no parameters key at all' do
      allow(task).to receive(:get_node_classification).and_return('groups' => [])

      expect(STDOUT).not_to receive(:puts)
      expect { task.execute! }.not_to raise_error
    end

    # Catches a mutation that drops the `next unless
    # node_classification['parameters'].key?('pe_master')` guard.
    it 'does not pin a node whose parameters hash has no pe_master key' do
      allow(task).to receive(:get_node_classification).and_return('groups' => [], 'parameters' => { 'other' => 'x' })

      expect(STDOUT).not_to receive(:puts)
      task.execute!
    end

    # Catches a mutation that inverts the `return unless
    # !pinned_nodes.empty?` guard, which would always print the warning
    # banner even with zero pinned nodes.
    it 'prints nothing when no legacy compilers are pinned as primary nodes' do
      allow(task).to receive(:get_node_classification).and_return('groups' => [])

      expect(STDOUT).not_to receive(:puts)
      task.execute!
    end

    # Catches a mutation that changes the join separator or drops a line
    # of the three-line warning.
    it 'prints the full three-line warning with comma-joined certnames when nodes are pinned' do
      multi_task = described_class.new('legacy_compilers' => 'a.example.com,b.example.com')
      allow(multi_task).to receive(:get_node_classification).and_return('groups' => [{ 'name' => 'PE Master' }])

      expect(STDOUT).to receive(:puts).with('The following legacy compilers are classified as Puppet primary nodes:')
      expect(STDOUT).to receive(:puts).with('a.example.com, b.example.com')
      expect(STDOUT).to receive(:puts).with('To continue with the upgrade, ensure that these compilers are no longer recognized as Puppet primary nodes.')

      multi_task.execute!
    end
  end

  describe '#get_node_classification' do
    subject(:task) { described_class.new('legacy_compilers' => 'legacy-a.example.com') }

    let(:https_dbl) { instance_double(Net::HTTP) }
    let(:request_dbl) { instance_double(Net::HTTP::Post) }

    before(:each) do
      allow(Puppet).to receive(:settings).and_return(hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                      hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem')
      allow(File).to receive(:read).and_return('dummy-pem-contents')
      allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
      allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))
      # NOTE: unlike every sibling task, #https here hardcodes 'localhost'
      # (not Puppet.settings[:certname]) and uses VERIFY_NONE with no
      # ca_file -- both asymmetries worth flagging in review, not fixed
      # here since this ticket is scoped to adding test coverage, not
      # correcting production behavior.
      allow(Net::HTTP).to receive(:new).with('localhost', 4433).and_return(https_dbl)
      allow(https_dbl).to receive(:use_ssl=)
      allow(https_dbl).to receive(:cert=)
      allow(https_dbl).to receive(:key=)
      allow(https_dbl).to receive(:verify_mode=)
    end

    # Catches a mutation that builds the wrong classifier URL, or that
    # POSTs a single batched request instead of one per certname.
    it 'POSTs to /classifier-api/v2/classified/nodes/<certname> for the given node' do
      allow(Net::HTTP::Post).to receive(:new).with('/classifier-api/v2/classified/nodes/legacy-a.example.com').and_return(request_dbl)
      allow(request_dbl).to receive(:[]=)
      response = instance_double(Net::HTTPOK, body: { 'groups' => [] }.to_json)
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)

      expect(task.get_node_classification('legacy-a.example.com')).to eq('groups' => [])
    end
  end
end
