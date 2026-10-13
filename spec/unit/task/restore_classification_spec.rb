require 'spec_helper'
require_relative '../../../tasks/restore_classification'

describe RestoreClassification do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'classification_file' => '/tmp/backup/classification_backup.json' } }
  let(:https_dbl) { instance_double(Net::HTTP) }
  let(:request_dbl) { instance_double(Net::HTTP::Post) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com',
                                                    hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                    hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
                                                    localcacert: '/etc/puppetlabs/puppet/ssl/certs/ca.pem')
    allow(File).to receive(:read).with('/etc/puppetlabs/puppet/ssl/certs/primary.pem').and_return('dummy-pem-contents')
    allow(File).to receive(:read).with('/etc/puppetlabs/puppet/ssl/private_keys/primary.pem').and_return('dummy-pem-contents')
    allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
    allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))
    allow(Net::HTTP).to receive(:new).with('primary.example.com', 4433).and_return(https_dbl)
    allow(https_dbl).to receive(:use_ssl=)
    allow(https_dbl).to receive(:cert=)
    allow(https_dbl).to receive(:key=)
    allow(https_dbl).to receive(:verify_mode=)
    allow(https_dbl).to receive(:ca_file=)
    allow(Net::HTTP::Post).to receive(:new)
      .with('/classifier-api/v1/import-hierarchy', 'Content-Type' => 'application/json')
      .and_return(request_dbl)
    allow(request_dbl).to receive(:body=)
    allow(https_dbl).to receive(:request).with(request_dbl)
  end

  # Catches a mutation that reserializes the file contents (subtly
  # reordering keys/whitespace) instead of forwarding the raw file body
  # byte-for-byte as the POST request body.
  it 'posts the exact raw contents of classification_file as the request body (not reserialized JSON)' do
    raw_body = '{"weird":   "spacing",   "order"  :1}'
    allow(File).to receive(:read).with('/tmp/backup/classification_backup.json').and_return(raw_body)

    expect(request_dbl).to receive(:body=).with(raw_body)

    task.execute!
  end

  # Catches a mutation that posts to the wrong classifier endpoint or
  # drops the JSON content-type header.
  it 'posts to the import-hierarchy endpoint with a JSON content-type' do
    allow(File).to receive(:read).with('/tmp/backup/classification_backup.json').and_return('{}')
    expect(Net::HTTP::Post).to receive(:new)
      .with('/classifier-api/v1/import-hierarchy', 'Content-Type' => 'application/json')
      .and_return(request_dbl)

    task.execute!
  end

  # Catches a mutation that omits the confirmation message or prints the
  # wrong path.
  it 'prints a confirmation message with the exact classification_file path' do
    allow(File).to receive(:read).with('/tmp/backup/classification_backup.json').and_return('{}')

    expect(STDOUT).to receive(:puts).with('Classification restored from /tmp/backup/classification_backup.json')

    task.execute!
  end

  # Catches a mutation that hardcodes a fixed classification_file path
  # instead of interpolating the param.
  context 'with a different classification_file param' do
    let(:params) { { 'classification_file' => '/custom/restore/path.json' } }

    it 'reads from and reports the path derived from that param' do
      allow(File).to receive(:read).with('/custom/restore/path.json').and_return('{}')

      expect(STDOUT).to receive(:puts).with('Classification restored from /custom/restore/path.json')

      task.execute!
    end
  end

  # Pins a real, pre-existing gap rather than fixing it: the classifier
  # API's response is never checked, so execute! unconditionally prints
  # the "restored" confirmation message and returns normally even when the
  # import request fails (4xx/5xx) -- unlike every sibling task touched by
  # this ticket (pe_ldap_config.rb, node_group_unpin.rb,
  # update_pe_master_rules.rb), which all raise on a non-success response.
  # Unchanged by this ticket's structural-only comment fix.
  it 'reports success even when the classifier API responds with an error' do
    allow(File).to receive(:read).with('/tmp/backup/classification_backup.json').and_return('{}')
    allow(https_dbl).to receive(:request).with(request_dbl).and_return(instance_double(Net::HTTPServerError, code: '500', body: 'boom'))

    expect(STDOUT).to receive(:puts).with('Classification restored from /tmp/backup/classification_backup.json')
    expect { task.execute! }.not_to raise_error
  end
end
