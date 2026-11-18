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
  let(:url) { 'https://primary.example.com:4433/classifier-api/v1/groups' }

  let(:known_hosts) do
    [{ 'name' => 'github.com', 'type' => 'ssh-ed25519', 'key' => 'AAAAC3Nza' }]
  end

  let(:carried) do
    {
      'r10k_remote' => 'git@github.com:example/control-repo.git',
      'r10k_private_key' => '/etc/puppetlabs/puppetserver/ssh/id-control_repo.rsa',
      'r10k_known_hosts' => known_hosts,
      'r10k_git_provider' => 'rugged',
    }
  end

  def pe_master(classes: {}, config_data: nil)
    group = { 'name' => 'PE Master', 'classes' => classes }
    group['config_data'] = config_data if config_data
    [{ 'name' => 'PE Infrastructure', 'classes' => {} }, group]
  end

  def profile(params)
    { 'puppet_enterprise::profile::master' => params }
  end

  # A real Net::HTTPResponse subclass, so the task's is_a?(Net::HTTPSuccess)
  # check sees the true class; only the body is stubbed.
  def stub_response(klass, body)
    response = klass.new('1.1', (klass == Net::HTTPOK) ? '200' : '503', 'status')
    allow(response).to receive(:body).and_return(body)
    allow(https_dbl).to receive(:get).with('/classifier-api/v1/groups').and_return(response)
  end

  def stub_groups(groups)
    stub_response(Net::HTTPOK, groups.to_json)
  end

  # Runs the task and returns every line it printed to stdout, and its exit
  # status (nil when it did not exit).
  def run_task
    output = []
    allow(STDOUT).to receive(:puts) { |s| output << s }
    status = nil
    begin
      task.execute!
    rescue SystemExit => e
      status = e.status
    end
    [output, status]
  end

  def expect_error(msg_parts, kind)
    output, status = run_task
    expect(status).to eq(1)
    expect(output.size).to eq(1)
    error = JSON.parse(output.first)['_error']
    expect(error['kind']).to eq(kind)
    expect(error['msg']).to include(*msg_parts)
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

  it 'returns the carried settings under _sensitive, and names only for the others' do
    stub_groups(pe_master(classes: profile(carried.merge(
      'r10k_proxy' => 'http://user:SECRET@proxy.example.com:3128',
      'r10k_postrun' => ['/bin/notify-SECRET'],
      'code_manager_auto_configure' => true,
      'code_manager_certname' => 'SECRET.example.com',
      'r10k_trace' => false,
      'replication_mode' => 'none',
      'java_args' => { 'Xmx' => '2g' },
    ))))

    output, status = run_task

    expect(status).to be_nil
    expect(output.size).to eq(1)
    expect(JSON.parse(output.first)).to eq(
      '_sensitive' => { 'settings' => carried },
      'not_carried' => [
        'puppet_enterprise::profile::master::r10k_proxy',
        'puppet_enterprise::profile::master::r10k_postrun',
        'puppet_enterprise::profile::master::code_manager_certname',
        'puppet_enterprise::profile::master::r10k_trace',
      ],
    )
    expect(output.first).not_to include('SECRET')
  end

  it "carries settings from PE Master's configuration data for the profile class, class parameters first" do
    stub_groups(pe_master(
      classes: profile('r10k_remote' => 'https://class.example.com/control.git'),
      config_data: {
        'puppet_enterprise::profile::master' => {
          'r10k_remote' => 'https://data.example.com/control.git',
          'r10k_private_key' => '/etc/puppetlabs/puppetserver/ssh/data.rsa',
        },
      },
    ))

    output, = run_task

    expect(JSON.parse(output.first)).to eq(
      '_sensitive' => {
        'settings' => {
          'r10k_remote' => 'https://class.example.com/control.git',
          'r10k_private_key' => '/etc/puppetlabs/puppetserver/ssh/data.rsa',
        },
      },
      'not_carried' => [],
    )
  end

  it 'does not name settings that are empty' do
    stub_groups(pe_master(classes: profile('r10k_postrun' => [], 'r10k_proxy' => '')))

    output, = run_task

    expect(JSON.parse(output.first)['not_carried']).to eq([])
  end

  it 'leaves out settings that are not set or are null' do
    stub_groups(pe_master(classes: profile('r10k_remote' => 'https://git.example.com/control.git', 'r10k_proxy' => nil)))

    output, = run_task

    expect(JSON.parse(output.first)).to eq(
      '_sensitive' => { 'settings' => { 'r10k_remote' => 'https://git.example.com/control.git' } },
      'not_carried' => [],
    )
  end

  it "names Code Manager entries in PE Master's configuration data, without their values" do
    stub_groups(pe_master(
      classes: profile(carried),
      config_data: {
        'puppet_enterprise::master::code_manager' => { 'sources' => { 'a' => { 'remote' => 'SECRET' } } },
        'puppet_enterprise::master::code_management' => { 'git_private_key' => '/SECRET' },
        'puppet_enterprise::profile::master' => {
          'r10k_proxy' => 'SECRET',
          'code_manager_certname' => 'SECRET',
          'code_manager_auto_configure' => true,
          'java_args' => {},
        },
        'puppet_enterprise::profile::console' => { 'r10k_unrelated' => 'x' },
        'puppet_enterprise::master::code_manager_unrelated' => 'not a hash',
      },
    ))

    output, = run_task

    expect(JSON.parse(output.first)['not_carried']).to eq([
                                                            'puppet_enterprise::master::code_manager::sources',
                                                            'puppet_enterprise::master::code_management::git_private_key',
                                                            'puppet_enterprise::profile::master::r10k_proxy',
                                                            'puppet_enterprise::profile::master::code_manager_certname',
                                                          ])
    expect(output.first).not_to include('SECRET')
  end

  it 'returns no settings when PE Master has no puppet_enterprise::profile::master class' do
    stub_groups(pe_master)

    output, = run_task

    expect(JSON.parse(output.first)).to eq('_sensitive' => { 'settings' => {} }, 'not_carried' => [])
  end

  it 'fails when there is no PE Master group' do
    stub_groups([{ 'name' => 'PE Infrastructure', 'classes' => {} }])

    expect_error(["The classifier at #{url} has no 'PE Master' node group."], 'peadm/pe-master-group-missing')
  end

  it 'fails with only the _error JSON on stdout when the classifier returns an error' do
    stub_response(Net::HTTPServiceUnavailable, 'classifier is down')

    expect_error(["Classifier returned HTTP 503 for #{url}: classifier is down"], 'peadm/classifier-request-failed')
  end

  it 'cuts a long error body short' do
    stub_response(Net::HTTPServiceUnavailable, 'x' * 2000)

    output, = run_task

    msg = JSON.parse(output.first)['_error']['msg']
    expect(msg).to end_with("#{'x' * 500}...")
    expect(msg.length).to be < 700
  end

  it 'reports an unexpected error as _error JSON' do
    stub_response(Net::HTTPOK, { 'not' => 'an array' }.to_json)

    expect_error(['Unexpected error reading the Code Manager settings', 'TypeError'], 'peadm/classifier-request-failed')
  end

  it 'fails when the classifier returns a body that is not JSON' do
    stub_response(Net::HTTPOK, '<html>proxy page</html>')

    expect_error(["Classifier returned a response that is not JSON for #{url}"], 'peadm/classifier-request-failed')
  end

  [
    [Errno::ECONNREFUSED, 'connect(2) for primary.example.com port 4433', 'Connection refused'],
    [SocketError, 'getaddrinfo: Name or service not known', 'getaddrinfo'],
    [Net::OpenTimeout, 'execution expired', 'execution expired'],
    [OpenSSL::SSL::SSLError, 'certificate verify failed', 'certificate verify failed'],
  ].each do |error_class, message, expected|
    it "fails with the _error JSON when the classifier cannot be reached (#{error_class})" do
      allow(https_dbl).to receive(:get).and_raise(error_class, message)

      expect_error(["Could not reach the classifier at #{url}", expected], 'peadm/classifier-request-failed')
    end
  end

  it 'reports a missing certificate file as a certificate error, not a network one' do
    allow(File).to receive(:read).with('/etc/puppetlabs/puppet/ssl/certs/primary.pem')
                                 .and_raise(Errno::ENOENT, '/etc/puppetlabs/puppet/ssl/certs/primary.pem')

    expect_error(["Could not load this node's certificate or key", 'No such file or directory'], 'peadm/certificate-error')
  end

  it 'verifies the classifier certificate' do
    stub_groups(pe_master)
    expect(https_dbl).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)

    run_task
  end
end
