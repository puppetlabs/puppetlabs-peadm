require 'spec_helper'
require_relative '../../../tasks/get_group_rules'

# tasks/get_group_rules.rb really does define GetInfrastructureAgentGroupRules,
# not GetGroupRules -- the class name doesn't match the task's filename.
# This spec file is intentionally named after the task file (get_group_rules.rb),
# matching this repo's house convention (see e.g. sign_csr_spec.rb,
# ssl_clean_spec.rb), not RuboCop's auto-derived snake_case of the class name.
# rubocop:disable RSpec/SpecFilePathFormat
describe GetInfrastructureAgentGroupRules do
  subject(:task) { described_class.new }

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

  # Catches a mutation that pretty-prints the entire group object instead
  # of just its 'rule' key.
  it "prints only the group's rule array, pretty-printed, when the PE Infrastructure Agent group exists" do
    response = instance_double(Net::HTTPOK, body: [{ 'name' => 'PE Infrastructure Agent', 'rule' => ['and'] }].to_json)
    allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

    expect(STDOUT).to receive(:puts).with(JSON.pretty_generate(['and']))

    task.execute!
  end

  # Catches a mutation that drops this fallback and instead raises/crashes,
  # or that changes the error message text a scripted consumer might grep
  # for.
  it 'prints a pretty-printed error hash when no PE Infrastructure Agent group exists' do
    response = instance_double(Net::HTTPOK, body: [{ 'name' => 'Other Group', 'rule' => [] }].to_json)
    allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

    expect(STDOUT).to receive(:puts).with(JSON.pretty_generate('error' => 'PE Infrastructure Agent group does not exist'))

    task.execute!
  end

  # Catches a mutation that swaps JSON.pretty_generate for plain .to_json --
  # this file is the outlier among its siblings in using pretty_generate,
  # and any doc/example showing this task's literal CLI output format
  # depends on the multi-line indented shape.
  it 'uses multi-line pretty-printed JSON, not compact single-line JSON' do
    response = instance_double(Net::HTTPOK, body: [{ 'name' => 'PE Infrastructure Agent', 'rule' => ['and', ['or']] }].to_json)
    allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)

    expect(STDOUT).to receive(:puts) do |output|
      expect(output).to include("\n")
    end

    task.execute!
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
