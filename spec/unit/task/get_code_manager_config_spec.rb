# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tasks/get_code_manager_config'

# PE-45912: peadm::migrate reads the old primary's Code Manager settings with
# this task, so it can install the new primary with the same r10k remote.
describe GetCodeManagerConfig do
  # A plain `let`, not `subject`: examples stub methods on this object, which
  # RuboCop's RSpec/SubjectStub cop disallows on the example group's subject.
  let(:task) { described_class.new }

  let(:https_dbl) { instance_double(Net::HTTP) }

  let(:known_hosts) do
    [{ 'name' => 'github.com', 'type' => 'ssh-ed25519', 'key' => 'AAAAC3Nza' }]
  end

  let(:pe_master_params) do
    {
      'code_manager_auto_configure' => true,
      'r10k_remote' => 'git@github.com:example/control-repo.git',
      'r10k_private_key' => '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa',
      'r10k_known_hosts' => known_hosts,
      'r10k_git_provider' => 'rugged',
      'r10k_proxy' => 'http://proxy.example.com:3128',
      'r10k_postrun' => ['/bin/true'],
      'replication_mode' => 'none',
      'check_for_updates' => false,
    }
  end

  def groups_with_pe_master(params)
    [
      { 'name' => 'PE Infrastructure', 'classes' => {} },
      { 'name' => 'PE Master', 'classes' => { 'puppet_enterprise::profile::master' => params } },
    ]
  end

  # A real Net::HTTPResponse subclass, so the task's is_a?(Net::HTTPSuccess)
  # check sees the true class; only the body is stubbed.
  def stub_response(klass, body)
    response = klass.new('1.1', (klass == Net::HTTPOK) ? '200' : '503', 'status')
    allow(response).to receive(:body).and_return(body)
    allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)
  end

  def run_task
    output = nil
    allow(STDOUT).to receive(:puts) { |s| output = s }
    task.execute!
    JSON.parse(output)
  end

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

  it "returns only the r10k settings from PE Master's puppet_enterprise::profile::master class" do
    stub_response(Net::HTTPOK, groups_with_pe_master(pe_master_params).to_json)

    expect(run_task).to eq(
      'params' => {
        'r10k_remote' => 'git@github.com:example/control-repo.git',
        'r10k_private_key' => '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa',
        'r10k_known_hosts' => known_hosts,
        'r10k_git_provider' => 'rugged',
        'r10k_proxy' => 'http://proxy.example.com:3128',
        'r10k_postrun' => ['/bin/true'],
      },
    )
  end

  it 'returns only the settings that are set' do
    stub_response(Net::HTTPOK, groups_with_pe_master('r10k_remote' => 'https://git.example.com/control.git').to_json)

    expect(run_task).to eq('params' => { 'r10k_remote' => 'https://git.example.com/control.git' })
  end

  it 'returns no settings when PE Master has no puppet_enterprise::profile::master class' do
    stub_response(Net::HTTPOK, [{ 'name' => 'PE Master', 'classes' => {} }].to_json)

    expect(run_task).to eq('params' => {})
  end

  it 'returns no settings when there is no PE Master group' do
    stub_response(Net::HTTPOK, [{ 'name' => 'PE Infrastructure', 'classes' => {} }].to_json)

    expect(run_task).to eq('params' => {})
  end

  it 'fails with only the _error JSON on stdout when the classifier returns an error' do
    stub_response(Net::HTTPServiceUnavailable, 'classifier is down')
    output = []
    allow(STDOUT).to receive(:puts) { |s| output << s }

    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    expect(output.size).to eq(1)
    expect(JSON.parse(output.first)).to eq(
      '_error' => {
        'msg' => 'Classifier returned HTTP 503 for /classifier-api/v1/groups: classifier is down',
        'kind' => 'peadm/classifier-request-failed',
      },
    )
  end

  it 'fails with the _error JSON when the classifier cannot be reached' do
    allow(https_dbl).to receive(:get).and_raise(Errno::ECONNREFUSED, 'connect(2) for primary.example.com port 4433')
    output = []
    allow(STDOUT).to receive(:puts) { |s| output << s }

    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    error = JSON.parse(output.first)['_error']
    expect(error['kind']).to eq('peadm/classifier-request-failed')
    expect(error['msg']).to include('Could not reach the classifier', 'Connection refused')
  end
end
