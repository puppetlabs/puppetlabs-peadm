require 'spec_helper'
require_relative '../../../tasks/pe_ldap_config'

describe PeLdapConfig do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'ldap_config' => { 'host' => 'ldap.example.com' }, 'pe_main' => 'primary.example.com', 'pe_version' => pe_version } }
  let(:pe_version) { '2023.8.0' }
  let(:https_dbl) { instance_double(Net::HTTP) }
  let(:request_dbl) { instance_double(Net::HTTP::Post) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppet', 'config', 'print', 'localcacert')
                                      .and_return(["/etc/puppetlabs/puppet/ssl/certs/ca.pem\n", instance_double(Process::Status, success?: true)])
    allow(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppet', 'config', 'print', 'hostcert')
                                      .and_return(["/etc/puppetlabs/puppet/ssl/certs/primary.pem\n", instance_double(Process::Status, success?: true)])
    allow(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppet', 'config', 'print', 'hostprivkey')
                                      .and_return(["/etc/puppetlabs/puppet/ssl/private_keys/primary.pem\n", instance_double(Process::Status, success?: true)])
    allow(File).to receive(:read).and_return('dummy-pem-contents')
    allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))
    allow(Net::HTTP).to receive(:new).with('primary.example.com', '4433').and_return(https_dbl)
    allow(https_dbl).to receive(:use_ssl=)
    allow(https_dbl).to receive(:verify_mode=)
    allow(https_dbl).to receive(:ca_file=)
    allow(https_dbl).to receive(:cert=)
    allow(https_dbl).to receive(:key=)
    allow(Net::HTTP::Post).to receive(:new).and_return(request_dbl)
    allow(Net::HTTP::Put).to receive(:new).and_return(request_dbl)
    allow(request_dbl).to receive(:body=)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(instance_double(Net::HTTPOK, body: '{}', code: '200'))
  end

  # Catches a mutation that flips the version comparison or its boundary,
  # routing a pre-2023.8.0 PE version to the wrong endpoint/verb.
  context 'when pe_version is older than 2023.8.0' do
    let(:pe_version) { '2023.7.1' }

    it 'PUTs to the legacy rbac-api/v1/ds endpoint' do
      expect(Net::HTTP::Put).to receive(:new).with(URI('https://primary.example.com:4433/rbac-api/v1/ds'), 'Content-type' => 'application/json').and_return(request_dbl)

      task.execute!
    end
  end

  # Catches a mutation that routes the current (>= 2023.8.0) endpoint to
  # the legacy path/verb instead -- 2023.8.0 itself is the boundary and
  # must take the "new" branch (the comparison is strictly "<").
  context 'when pe_version is exactly 2023.8.0' do
    let(:pe_version) { '2023.8.0' }

    it 'POSTs to the current rbac-api/v1/command/ldap/create endpoint' do
      expect(Net::HTTP::Post).to receive(:new).with(URI('https://primary.example.com:4433/rbac-api/v1/command/ldap/create'), 'Content-type' => 'application/json').and_return(request_dbl)

      task.execute!
    end
  end

  context 'when pe_version is newer than 2023.8.0' do
    let(:pe_version) { '2025.11.3' }

    it 'POSTs to the current rbac-api/v1/command/ldap/create endpoint' do
      expect(Net::HTTP::Post).to receive(:new).with(URI('https://primary.example.com:4433/rbac-api/v1/command/ldap/create'), 'Content-type' => 'application/json').and_return(request_dbl)

      task.execute!
    end
  end

  # Catches a mutation that drops any one of the three distinct file-path
  # lookups' own targeted error message.
  it 'raises a targeted error when the CA file path lookup fails' do
    allow(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppet', 'config', 'print', 'localcacert')
                                      .and_return(['', instance_double(Process::Status, success?: false)])

    expect { task.execute! }.to raise_error('Could not get the CA file path.')
  end

  it 'raises a targeted error when the cert file path lookup fails' do
    allow(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppet', 'config', 'print', 'hostcert')
                                      .and_return(['', instance_double(Process::Status, success?: false)])

    expect { task.execute! }.to raise_error('Could not get the Cert file path.')
  end

  it 'raises a targeted error when the key file path lookup fails' do
    allow(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppet', 'config', 'print', 'hostprivkey')
                                      .and_return(['', instance_double(Process::Status, success?: false)])

    expect { task.execute! }.to raise_error('Could not get the Key file path.')
  end

  # Catches a mutation that sends the raw ldap_config Hash (or a
  # differently-shaped body) instead of its JSON serialization.
  it 'sends the ldap_config param as the JSON request body' do
    expect(request_dbl).to receive(:body=).with('{"host":"ldap.example.com"}')

    task.execute!
  end

  # PE-47523: the task's output goes into bolt-debug.log, so it never prints
  # the response body. RBAC's error bodies can echo the submitted request,
  # bind password included (schema-violation's details.submitted).
  #
  # Catches a mutation that drops the non-200 check, silently accepting
  # any response code as success.
  it 'raises with the code and error kind, without printing the body, when the API responds with a non-200 code' do
    body = '{"kind":"puppetlabs.rbac/schema-violation","msg":"bad","details":{"submitted":{"password":"bind-canary"}}}'
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(instance_double(Net::HTTPBadRequest, body: body, code: '400'))

    expect(STDOUT).not_to receive(:puts)
    expect { task.execute! }.to raise_error('API response code 400 (puppetlabs.rbac/schema-violation)')
  end

  it 'raises with just the code when the error body is not JSON' do
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(instance_double(Net::HTTPServerError, body: '<html>boom</html>', code: '500'))

    expect { task.execute! }.to raise_error('API response code 500')
  end

  # On PE before 2023.8 the legacy ds endpoint returns the settings it
  # saved, bind password included.
  #
  # Catches a mutation that raises even on success.
  it 'prints only the status, not the response body, when the API responds 200' do
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(instance_double(Net::HTTPOK, body: '{"password":"bind-canary"}', code: '200'))

    expect(STDOUT).to receive(:puts).with('{"status":"200"}')
    expect { task.execute! }.not_to raise_error
  end
end
