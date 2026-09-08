require 'spec_helper'
require_relative '../../../tasks/code_manager_enabled'

describe CodeManagerEnabled do
  # NOTE: no initialize/params by design -- this task's JSON declares
  # "parameters": {} and its sole call site (plans/add_replica.pp:27) never
  # passes any; confirmed intentional, not a gap.
  #
  # A plain `let`, not `subject` -- #groups and #execute! below stub
  # methods on this object, and RuboCop's RSpec/SubjectStub cop disallows
  # stubbing methods on the object under test when it's registered as the
  # example group's `subject`.
  let(:task) { described_class.new }

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

  describe '#groups' do
    # Catches a mutation that drops the @groups ||= memoization, causing a
    # duplicate classifier round-trip.
    it 'memoizes the classifier round-trip across repeated calls' do
      response = instance_double(Net::HTTPOK, body: [{ 'name' => 'PE Master' }].to_json)
      expect(https_dbl).to receive(:get).with('/classifier-api/v1/groups').once.and_return(response)

      task.groups
      task.groups
    end
  end

  describe '#execute!' do
    def stub_groups(value)
      allow(task).to receive(:groups).and_return(
        CodeManagerEnabled::NodeGroup.new(
          [{ 'name' => 'PE Master',
             'classes' => { 'puppet_enterprise::profile::master' => { 'code_manager_auto_configure' => value } } }],
        ),
      )
    end

    it 'reports code_manager_enabled true when the classified value is exactly true' do
      stub_groups(true)
      expect(STDOUT).to receive(:puts).with('{"code_manager_enabled":true}')
      task.execute!
    end

    # Catches a mutation that drops the strict `== true` comparison in
    # favor of bare truthiness, which would let a stringy "true" (a
    # plausible classifier config-data quirk) incorrectly report as
    # enabled.
    it 'reports code_manager_enabled false when the classified value is the string "true", not the boolean' do
      stub_groups('true')
      expect(STDOUT).to receive(:puts).with('{"code_manager_enabled":false}')
      task.execute!
    end

    # Catches a mutation that inverts the comparison outright.
    it 'reports code_manager_enabled false when the classified value is false' do
      stub_groups(false)
      expect(STDOUT).to receive(:puts).with('{"code_manager_enabled":false}')
      task.execute!
    end

    it 'reports code_manager_enabled false when the group/class/param is absent entirely' do
      allow(task).to receive(:groups).and_return(CodeManagerEnabled::NodeGroup.new([]))
      expect(STDOUT).to receive(:puts).with('{"code_manager_enabled":false}')
      task.execute!
    end
  end

  describe CodeManagerEnabled::NodeGroup do
    # Minimal spot-check -- the full dig battery (nil-group, whole-group,
    # multi-level drill-down) is already covered for get_peadm_config.rb's
    # identical (duplicated, not shared -- dedup is out of scope)
    # implementation in get_peadm_config_spec.rb.
    it 'returns nil when no group matches the name' do
      expect(described_class.new([]).dig('Nonexistent')).to be_nil
    end

    it 'delegates to Hash#dig(*args) on the matched group when args are given' do
      data = [{ 'name' => 'PE Master', 'classes' => { 'foo' => { 'bar' => 'baz' } } }]
      expect(described_class.new(data).dig('PE Master', 'classes', 'foo', 'bar')).to eq('baz')
    end
  end
end
