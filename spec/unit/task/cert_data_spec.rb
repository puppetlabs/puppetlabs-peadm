require 'spec_helper'
require 'yaml'
require_relative '../../../tasks/cert_data'

describe CertData do
  # NOTE: this task's parameters JSON declares {} and no plan call site
  # passes any params -- @params is stored in initialize but never read by
  # any method in this class, matching code_manager_enabled.rb's
  # intentional-by-design "no meaningful params" shape.
  subject(:task) { described_class.new({}) }

  let(:settings) do
    {
      hostcert: '/etc/puppetlabs/puppet/ssl/certs/agent.pem',
      csr_attributes: '/etc/puppetlabs/puppet/csr_attributes.yaml',
      dns_alt_names: 'alt1.example.com,alt2.example.com',
      certname: 'agent.example.com',
    }
  end

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(settings)
    allow(settings).to receive(:use)
  end

  # Builds a real, minimally-valid self-signed certificate so
  # extensions_from_x509_certificate/alt_names_from_x509_certificate exercise
  # real ASN1/X509 parsing rather than a hand-mocked double.
  def build_cert(extensions: [])
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('/CN=agent.example.com')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    extensions.each { |ext| cert.add_extension(ext) }
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert
  end

  # Mirrors Puppet::SSL::CertificateRequest's own encoding for custom
  # ppCertExt-family extension values (see puppet/ssl/certificate_request.rb):
  # a raw ASN1 UTF8String DER, which is exactly what
  # extensions_from_x509_certificate's `ext.value[2..-1]` slice expects
  # (strip the 2-byte tag+length header, keep the string content).
  def custom_extension(oid, value)
    OpenSSL::X509::Extension.new(oid, OpenSSL::ASN1::UTF8String.new(value).to_der, false)
  end

  describe '#execute!' do
    # Catches a mutation that inverts the File.exist?(certpath) branch,
    # mixing up the "real cert" and "CSR fallback" code paths.
    it 'uses the certificate branch, with certname/extensions/dns-alt-names derived from the cert, when the hostcert exists' do
      cert = build_cert
      allow(File).to receive(:exist?).with('/etc/puppetlabs/puppet/ssl/certs/agent.pem').and_return(true)
      allow(File).to receive(:read).with('/etc/puppetlabs/puppet/ssl/certs/agent.pem').and_return(cert.to_pem)

      expect(STDOUT).to receive(:puts) do |json_str|
        parsed = JSON.parse(json_str)
        expect(parsed['certificate-exists']).to eq(true)
        expect(parsed['certname']).to eq('agent.example.com')
        expect(parsed['dns-alt-names']).to eq([])
      end

      task.execute!
    end

    # Catches a mutation that reads cert-branch fields even when there is
    # no cert, and a mutation that drops .split(',') on dns_alt_names.
    it 'uses the CSR-fallback branch, sourcing certname/dns-alt-names from Puppet.settings, when the hostcert does not exist' do
      allow(File).to receive(:exist?).with('/etc/puppetlabs/puppet/ssl/certs/agent.pem').and_return(false)
      allow(File).to receive(:exist?).with('/etc/puppetlabs/puppet/csr_attributes.yaml').and_return(false)

      expect(STDOUT).to receive(:puts) do |json_str|
        parsed = JSON.parse(json_str)
        expect(parsed['certificate-exists']).to eq(false)
        expect(parsed['certname']).to eq('agent.example.com')
        expect(parsed['extensions']).to eq({})
        expect(parsed['dns-alt-names']).to eq(['alt1.example.com', 'alt2.example.com'])
      end

      task.execute!
    end
  end

  describe '#certname_from_x509_certificate' do
    # Catches a mutation that picks a different RDN component (e.g. 'O')
    # or the wrong array index.
    it 'extracts the CN RDN value from the certificate subject' do
      cert = build_cert
      expect(task.certname_from_x509_certificate(cert)).to eq('agent.example.com')
    end
  end

  describe '#extensions_from_x509_certificate' do
    # Catches a mutation that drops the [2..-1] slice (which strips the
    # ASN1 tag+length header) or that requires a friendly name to exist.
    it 'includes a custom ppCertExt-family extension with no friendly name, keyed only by raw OID' do
      cert = build_cert(extensions: [custom_extension('1.3.6.1.4.1.34380.1.1.9812', 'custom-value')])
      expect(task.extensions_from_x509_certificate(cert)).to eq('1.3.6.1.4.1.34380.1.1.9812' => 'custom-value')
    end

    # Catches a mutation that drops the friendly-name duplicate entry,
    # breaking any consumer that looks extensions up by short name.
    #
    # NOTE: uses a mocked extension/cert, not a real signed one like the
    # other tests here. Puppet's test harness (Puppet::Test::TestHelper,
    # invoked by puppetlabs_spec_helper/rspec-puppet during suite setup)
    # calls Puppet::SSL::Oids.register_puppet_oids once per process, which
    # registers known Puppet OIDs (like pp_uuid's 1.3.6.1.4.1.34380.1.1.1)
    # with OpenSSL's global object registry. Once registered, a REAL
    # signed cert's Extension#oid returns the friendly short name
    # ('pp_uuid') instead of the numeric OID for the rest of the process --
    # which fails this method's `ext.oid.start_with?('1.3.6.1.4.1.34380.1')`
    # guard and silently drops the extension entirely, unlike a bare
    # production Bolt task run (which never calls register_puppet_oids).
    # Mocking .oid/.value directly sidesteps that test-harness-only,
    # global-registry side effect and tests this method's own logic in
    # isolation instead.
    it 'double-keys a known Puppet OID by both raw OID and friendly name' do
      ext = instance_double(OpenSSL::X509::Extension, oid: '1.3.6.1.4.1.34380.1.1.1',
                                                        value: OpenSSL::ASN1::UTF8String.new('node-uuid-value').to_der)
      cert = instance_double(OpenSSL::X509::Certificate, extensions: [ext])

      expect(task.extensions_from_x509_certificate(cert)).to eq(
        '1.3.6.1.4.1.34380.1.1.1' => 'node-uuid-value',
        'pp_uuid' => 'node-uuid-value',
      )
    end

    # Catches a mutation that drops the `next memo unless
    # ext.oid.start_with?(...)` filter, leaking unrelated cert extensions
    # (like subjectAltName) into the task output.
    it 'excludes extensions whose OID does not start with the ppCertExt prefix' do
      san_ext = OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', 'DNS:excluded.example.com', false)
      cert = build_cert(extensions: [san_ext])

      expect(task.extensions_from_x509_certificate(cert)).to eq({})
    end
  end

  describe '#alt_names_from_x509_certificate' do
    # Catches a mutation that drops .flatten (returning nested arrays) or
    # the DNS: regex-slice (returning raw "DNS:foo.example.com" strings).
    it 'flattens multiple DNS entries from the subjectAltName extension, stripping the DNS: prefix' do
      san_ext = OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', 'DNS:one.example.com,DNS:two.example.com', false)
      cert = build_cert(extensions: [san_ext])

      expect(task.alt_names_from_x509_certificate(cert)).to eq(['one.example.com', 'two.example.com'])
    end

    # Catches a mutation that assumes the extension always exists and
    # blows up with a nil-dereference -- the code comment explicitly calls
    # out supporting certs with or without a subjectAltName extension.
    it 'returns an empty array when the certificate has no subjectAltName extension' do
      cert = build_cert
      expect(task.alt_names_from_x509_certificate(cert)).to eq([])
    end
  end

  describe '#extensions_from_csr_attributes_path' do
    # Catches a mutation that drops the `return {} unless File.exist?(path)`
    # guard, attempting to read/parse a nonexistent file.
    it 'returns {} when the CSR attributes file does not exist' do
      allow(File).to receive(:exist?).with('/nonexistent/csr_attributes.yaml').and_return(false)
      expect(task.extensions_from_csr_attributes_path('/nonexistent/csr_attributes.yaml')).to eq({})
    end

    # Catches a mutation that drops the oids[request] duplicate branch.
    it 'double-keys a known short-name extension request by both short name and numeric OID' do
      yaml = { 'extension_requests' => { 'pp_uuid' => 'node-uuid-value' } }.to_yaml
      allow(File).to receive(:exist?).with('/etc/puppetlabs/puppet/csr_attributes.yaml').and_return(true)
      allow(File).to receive(:read).with('/etc/puppetlabs/puppet/csr_attributes.yaml').and_return(yaml)

      expect(task.extensions_from_csr_attributes_path('/etc/puppetlabs/puppet/csr_attributes.yaml')).to eq(
        'pp_uuid' => 'node-uuid-value',
        '1.3.6.1.4.1.34380.1.1.1' => 'node-uuid-value',
      )
    end

    # Catches a mutation that always adds a spurious second key (e.g.
    # nil => value) even when there's no OID match for the request name.
    it 'does not add a spurious second key for a request name with no OID mapping' do
      yaml = { 'extension_requests' => { 'custom_field' => 'custom-value' } }.to_yaml
      allow(File).to receive(:exist?).with('/etc/puppetlabs/puppet/csr_attributes.yaml').and_return(true)
      allow(File).to receive(:read).with('/etc/puppetlabs/puppet/csr_attributes.yaml').and_return(yaml)

      expect(task.extensions_from_csr_attributes_path('/etc/puppetlabs/puppet/csr_attributes.yaml')).to eq('custom_field' => 'custom-value')
    end
  end

  describe '#x509_certificate_from_path' do
    # Defensive double-check of File.exist? even though execute! already
    # gates on it -- catches a mutation that lets File.read raise
    # Errno::ENOENT instead of short-circuiting to nil.
    it 'returns nil when the path does not exist' do
      allow(File).to receive(:exist?).with('/missing/path.pem').and_return(false)
      expect(task.x509_certificate_from_path('/missing/path.pem')).to be_nil
    end
  end
end
