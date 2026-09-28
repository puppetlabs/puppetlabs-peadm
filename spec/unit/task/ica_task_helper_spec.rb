# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'openssl'
require_relative '../../../files/ica_task_helper'

describe IcaTaskHelper do
  describe '.primary_https_client' do
    it 'builds an mTLS client using this node\'s agent certificate, key, and CA bundle' do
      Dir.mktmpdir do |dir|
        key = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=compiler-a.example.com')
        cert.public_key = key.public_key
        cert.not_before = Time.now
        cert.not_after = Time.now + 3600
        cert.serial = 1
        cert.version = 2
        cert.sign(key, OpenSSL::Digest.new('SHA256'))

        hostcert_path = File.join(dir, 'hostcert.pem')
        hostprivkey_path = File.join(dir, 'hostprivkey.pem')
        localcacert_path = File.join(dir, 'ca.pem')
        File.write(hostcert_path, cert.to_pem)
        File.write(hostprivkey_path, key.to_pem)
        File.write(localcacert_path, cert.to_pem)

        allow(Puppet).to receive(:settings).and_return(
          hostcert: hostcert_path,
          hostprivkey: hostprivkey_path,
          localcacert: localcacert_path,
        )

        https = described_class.primary_https_client('primary.example.com')

        expect(https.address).to eq('primary.example.com')
        expect(https.port).to eq(IcaTaskHelper::CA_SERVICE_PORT)
        expect(https.use_ssl?).to be(true)
        expect(https.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
        expect(https.ca_file).to eq(localcacert_path)
        expect(https.cert.subject.to_s).to eq('/CN=compiler-a.example.com')
        expect(https.key.to_pem).to eq(key.to_pem)
      end
    end

    it 'accepts an explicit port, overriding the CA service default' do
      allow(Puppet).to receive(:settings).and_return(hostcert: '/dev/null', hostprivkey: '/dev/null', localcacert: '/dev/null')
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with('/dev/null').and_return('')
      allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
      allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))

      https = described_class.primary_https_client('primary.example.com', 4433)

      expect(https.port).to eq(4433)
    end

    it 'sets a 10s open/read timeout, matching the same CA-service client in list_compiler_icas.rb' do
      allow(Puppet).to receive(:settings).and_return(hostcert: '/dev/null', hostprivkey: '/dev/null', localcacert: '/dev/null')
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with('/dev/null').and_return('')
      allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
      allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))

      https = described_class.primary_https_client('primary.example.com')

      expect(https.open_timeout).to eq(10)
      expect(https.read_timeout).to eq(10)
    end
  end

  describe '.classify_connection_error' do
    it 'classifies an SSL error as a TLS handshake failure' do
      msg, suffix = described_class.classify_connection_error(OpenSSL::SSL::SSLError.new('certificate verify failed'))
      expect(suffix).to eq('tls_failed')
      expect(msg).to include('TLS handshake with the primary failed')
      expect(msg).to include('certificate verify failed')
    end

    it 'classifies a connection-refused error as a connection failure' do
      msg, suffix = described_class.classify_connection_error(Errno::ECONNREFUSED.new)
      expect(suffix).to eq('connection_failed')
      expect(msg).to include('Failed to connect to the primary')
    end

    it 'classifies a read timeout as a connection failure' do
      msg, suffix = described_class.classify_connection_error(Net::ReadTimeout.new)
      expect(suffix).to eq('connection_failed')
      expect(msg).to include('Failed to connect to the primary')
    end
  end

  describe '.build_intermediate_ca_request' do
    it 'builds a GET request with no action and the RBAC token attached' do
      allow(described_class).to receive(:rbac_token).with('/home/user/.puppetlabs/token').and_return('sekrit-token')

      req = described_class.build_intermediate_ca_request(Net::HTTP::Get, 'compiler-a.example.com', '/home/user/.puppetlabs/token')

      expect(req).to be_a(Net::HTTP::Get)
      expect(req.path).to eq('/puppet-ca/v1/intermediate-ca/compiler-a.example.com')
      expect(req['X-Authentication']).to eq('sekrit-token')
    end

    it 'appends the action to the path for a POST request' do
      allow(described_class).to receive(:rbac_token).with(nil).and_return('sekrit-token')

      req = described_class.build_intermediate_ca_request(Net::HTTP::Post, 'compiler-a.example.com', nil, action: 'drain')

      expect(req).to be_a(Net::HTTP::Post)
      expect(req.path).to eq('/puppet-ca/v1/intermediate-ca/compiler-a.example.com/drain')
      expect(req['X-Authentication']).to eq('sekrit-token')
    end
  end

  describe '.fail!' do
    it 'writes the _error contract to STDOUT and exits 1' do
      expect(STDOUT).to receive(:puts).with(JSON.generate('_error' => { 'msg' => 'boom', 'kind' => 'peadm/some_failure' }))

      expect { described_class.fail!('boom', 'peadm/some_failure') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  describe '.validate_fqdn!' do
    it 'accepts a normal certname' do
      expect { described_class.validate_fqdn!('compiler-a.example.com') }.not_to raise_error
    end

    it 'rejects a value containing a CRLF' do
      expect { described_class.validate_fqdn!("compiler-a\r\nX-Injected: true") }.to raise_error(ArgumentError, %r{invalid compiler_fqdn})
    end

    it 'rejects a value containing a slash' do
      expect { described_class.validate_fqdn!('compiler-a/../revoke') }.to raise_error(ArgumentError, %r{invalid compiler_fqdn})
    end

    it 'rejects an empty string' do
      expect { described_class.validate_fqdn!('') }.to raise_error(ArgumentError, %r{invalid compiler_fqdn})
    end
  end

  describe '.rbac_token' do
    it 'reads and chomps the given token file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'token')
        File.write(path, "sekrit\n")
        expect(described_class.rbac_token(path)).to eq('sekrit')
      end
    end

    it 'falls back to default_token_file when none is given' do
      allow(described_class).to receive(:default_token_file).and_return('/fallback/token')
      allow(File).to receive(:read).with('/fallback/token').and_return("fallback-token\n")
      expect(described_class.rbac_token(nil)).to eq('fallback-token')
    end
  end

  describe '.revert_bootstrap_to_proxy!' do
    it 'returns false without writing anything when bootstrap.cfg does not exist' do
      allow(described_class).to receive(:bootstrap_cfg_path).and_return('/nonexistent/bootstrap.cfg')
      expect(File).not_to receive(:write)
      expect(described_class.revert_bootstrap_to_proxy!).to be(false)
    end

    it 'returns true and removes an uncommented intermediate-ca-service entry and adds the disabled-service entry' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'bootstrap.cfg')
        File.write(path, <<~CFG)
          puppetlabs.services.ca.certificate-authority-service/certificate-authority-service
          puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service
        CFG
        allow(described_class).to receive(:bootstrap_cfg_path).and_return(path)

        expect(described_class.revert_bootstrap_to_proxy!).to be(true)

        contents = File.read(path)
        expect(contents).not_to include('intermediate-ca-service/intermediate-ca-service')
        expect(contents).to include('certificate-authority-disabled-service/certificate-authority-disabled-service')
      end
    end

    it 'does not duplicate the disabled-service entry if already present' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'bootstrap.cfg')
        File.write(path, "puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
        allow(described_class).to receive(:bootstrap_cfg_path).and_return(path)

        described_class.revert_bootstrap_to_proxy!

        expect(File.read(path).scan('certificate-authority-disabled-service/certificate-authority-disabled-service').length).to eq(1)
      end
    end

    it 'adds the disabled-service entry on its own line even when the file has no trailing newline' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'bootstrap.cfg')
        File.write(path, 'puppetlabs.services.ca.certificate-authority-service/certificate-authority-service')
        allow(described_class).to receive(:bootstrap_cfg_path).and_return(path)

        described_class.revert_bootstrap_to_proxy!

        lines = File.readlines(path)
        expect(lines.last).to eq("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      end
    end

    it 'leaves a commented-out intermediate-ca-service entry alone' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'bootstrap.cfg')
        File.write(path, "# puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n")
        allow(described_class).to receive(:bootstrap_cfg_path).and_return(path)

        described_class.revert_bootstrap_to_proxy!

        expect(File.read(path)).to include('# puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service')
      end
    end
  end

  describe '.set_hocon_value! and .get_hocon_value' do
    it 'writes a new setting into a freshly-created file and reads it back' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ca.conf')

        described_class.set_hocon_value!(path, 'certificate-authority.proxy-target', 'primary')

        expect(described_class.get_hocon_value(path, 'certificate-authority.proxy-target')).to eq('primary')
      end
    end

    it 'preserves an unrelated existing setting when updating another' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ca.conf')
        File.write(path, "certificate-authority: {\n  ica-passphrase-path: \"/etc/puppetlabs/puppetserver/ssl/ica_passphrase\"\n}\n")

        described_class.set_hocon_value!(path, 'certificate-authority.proxy-target', 'primary')

        expect(described_class.get_hocon_value(path, 'certificate-authority.ica-passphrase-path'))
          .to eq('/etc/puppetlabs/puppetserver/ssl/ica_passphrase')
        expect(described_class.get_hocon_value(path, 'certificate-authority.proxy-target')).to eq('primary')
      end
    end

    it 'returns nil for a setting that does not exist' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ca.conf')
        File.write(path, "certificate-authority: {}\n")

        expect(described_class.get_hocon_value(path, 'certificate-authority.proxy-target')).to be_nil
      end
    end

    it 'returns nil when the file does not exist' do
      expect(described_class.get_hocon_value('/nonexistent/ca.conf', 'certificate-authority.proxy-target')).to be_nil
    end
  end
end
