require 'spec_helper'
require_relative '../../../tasks/backup_classification'

describe BackupClassification do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'directory' => '/tmp/backup' } }
  let(:https_dbl) { instance_double(Net::HTTP) }
  let(:request_dbl) { instance_double(Net::HTTP::Get) }

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
    allow(Net::HTTP::Get).to receive(:new).with('/classifier-api/v1/groups').and_return(request_dbl)
  end

  # Catches a mutation that reserializes the parsed JSON (subtly
  # reordering keys/whitespace) instead of forwarding the raw response
  # body byte-for-byte.
  it 'writes the exact raw response body (not reserialized JSON) to <directory>/classification_backup.json' do
    raw_body = '{"weird":   "spacing",   "order"  :1}'
    response = instance_double(Net::HTTPOK, body: raw_body)
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)

    expect(File).to receive(:write).with('/tmp/backup/classification_backup.json', raw_body)

    task.execute!
  end

  # Catches a mutation that omits the confirmation message or prints the
  # wrong path.
  it 'prints a confirmation message with the exact written path' do
    response = instance_double(Net::HTTPOK, body: '[]')
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)
    allow(File).to receive(:write)

    expect(STDOUT).to receive(:puts).with('Classification written to /tmp/backup/classification_backup.json')

    task.execute!
  end

  # Catches a mutation that hardcodes a fixed directory (e.g. /tmp)
  # instead of interpolating the directory param.
  context 'with a different directory param' do
    let(:params) { { 'directory' => '/custom/backup/path' } }

    it 'writes to the path derived from that directory' do
      response = instance_double(Net::HTTPOK, body: '[]')
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)

      expect(File).to receive(:write).with('/custom/backup/path/classification_backup.json', '[]')

      task.execute!
    end
  end
end
