# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../../tasks/install_ica_cert'

describe InstallIcaCert do
  subject(:task) { described_class.new('primary_host' => 'primary.example.com') }

  let(:https) { instance_double('Net::HTTP') }
  let(:own_cert_pem) { build_cert_pem('compiler-a.example.com') }
  let(:classifier_https) { instance_double('Net::HTTP') }
  let(:bootstrap_cfg) { Tempfile.new('bootstrap.cfg') }
  let(:ca_conf) { Tempfile.new('ca.conf') }
  # One key reused across fixtures: these tests turn on subject CN and
  # content equality, not on the key material itself.
  let(:signing_key) { OpenSSL::PKey::RSA.new(2048) }

  def build_cert_pem(cn)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(1..1_000_000)
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = cert.subject
    cert.public_key = signing_key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.sign(signing_key, OpenSSL::Digest.new('SHA256'))
    cert.to_pem
  end

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'compiler-a.example.com', confdir: '/etc/puppetlabs/puppetserver')
    allow(IcaTaskHelper).to receive_messages(
      bootstrap_cfg_path: bootstrap_cfg.path,
      ca_conf_path: ca_conf.path,
    )
    allow(IcaTaskHelper).to receive(:primary_https_client).with('primary.example.com', IcaTaskHelper::CA_SERVICE_PORT).and_return(https)
    allow(IcaTaskHelper).to receive(:primary_https_client).with('primary.example.com', IcaTaskHelper::CLASSIFIER_PORT).and_return(classifier_https)
    allow(IcaTaskHelper).to receive(:pin_to_ica_group!)
    allow(Open3).to receive(:capture2e).and_return(['', instance_double('Process::Status', success?: true)])
  end

  after(:each) do
    bootstrap_cfg.close!
    ca_conf.close!
  end

  context 'when already installed and the installed certificate matches what the primary reports as active' do
    it 'is a no-op and exits 0, without restarting the CA service' do
      bootstrap_cfg.write('puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service')
      bootstrap_cfg.rewind
      cert_file = Tempfile.new('ica.pem')
      cert_file.write(own_cert_pem)
      cert_file.rewind
      allow(task).to receive(:ica_cert_path).and_return(cert_file.path) # rubocop:disable RSpec/SubjectStub
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(true)

      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => own_cert_pem }.to_json)
      expect(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca/compiler-a.example.com').and_return(cert_response)
      expect(Open3).not_to receive(:capture2e)
      expect(IcaTaskHelper).not_to receive(:pin_to_ica_group!)
      expect(STDOUT).to receive(:puts).with(JSON.generate('status' => 'already-installed'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      cert_file.close!
    end
  end

  context 'when bootstrap.cfg already shows intermediate-ca-service but the installed certificate is missing or does not match' do
    # This is the state a run left behind if it crashed after swapping
    # bootstrap.cfg but before the CA service reload completed: the file at
    # ica_cert_path was never written (it's written last, after the reload
    # succeeds), so the comparison below correctly treats the promotion as
    # incomplete rather than trusting the bootstrap.cfg text alone.
    it 'redoes the remaining steps, restart included, rather than reporting a false already-installed' do
      bootstrap_cfg.write('puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service')
      bootstrap_cfg.rewind
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind
      cert_file = Tempfile.new('ica.pem')
      allow(task).to receive(:ica_cert_path).and_return(cert_file.path) # rubocop:disable RSpec/SubjectStub
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(true)

      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => own_cert_pem }.to_json)
      expect(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca/compiler-a.example.com').and_return(cert_response)
      expect(IcaTaskHelper).to receive(:pin_to_ica_group!).with(classifier_https, 'compiler-a.example.com')
      expect(Open3).to receive(:capture2e)
        .with('/opt/puppetlabs/bin/puppetserver', 'ca', 'reload')
        .and_return(['', instance_double('Process::Status', success?: true)])
      expect(STDOUT).to receive(:puts).with(JSON.generate('status' => 'installed'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }

      expect(File.read(cert_file.path)).to eq(own_cert_pem)
      expect(File.read(ca_conf.path)).not_to include('ica-pool')
      cert_file.close!
    end

    it 'still fails the task, with the previous state left in place, when the redone restart fails' do
      bootstrap_cfg.write('puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service')
      bootstrap_cfg.rewind
      cert_file = Tempfile.new('ica.pem')
      allow(task).to receive(:ica_cert_path).and_return(cert_file.path) # rubocop:disable RSpec/SubjectStub
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(true)

      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => own_cert_pem }.to_json)
      allow(https).to receive(:get).and_return(cert_response)
      expect(Open3).to receive(:capture2e)
        .with(IcaTaskHelper::PUPPETSERVER_BIN, 'ca', 'reload')
        .and_return(['reload refused', instance_double('Process::Status', success?: false)])
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/install_ica_cert_failed')
        expect(parsed['_error']['msg']).to include('Failed to reload CA service')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(File.exist?(cert_file.path) ? File.read(cert_file.path) : '').to eq('')
      cert_file.close!
    end
  end

  context 'when an active ICA is available on the primary' do
    it 'fetches the cert, pins the classifier group, clears ica-pool, swaps bootstrap.cfg, restarts the service, and installs the cert last' do
      bootstrap_cfg.write("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      bootstrap_cfg.rewind
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind

      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => own_cert_pem }.to_json)
      expect(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca/compiler-a.example.com').and_return(cert_response)

      cert_file = Tempfile.new('ica.pem')
      allow(task).to receive(:ica_cert_path).and_return(cert_file.path) # rubocop:disable RSpec/SubjectStub

      expect(IcaTaskHelper).to receive(:pin_to_ica_group!).with(classifier_https, 'compiler-a.example.com')
      expect(Open3).to receive(:capture2e)
        .with('/opt/puppetlabs/bin/puppetserver', 'ca', 'reload')
        .and_return(['', instance_double('Process::Status', success?: true)])
      expect(STDOUT).to receive(:puts).with(JSON.generate('status' => 'installed'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }

      expect(File.read(cert_file.path)).to eq(own_cert_pem)
      expect(File.read(bootstrap_cfg.path)).to include('intermediate-ca-service')
      expect(File.read(bootstrap_cfg.path)).not_to include('certificate-authority-disabled-service')
      expect(File.read(ca_conf.path)).not_to include('ica-pool')
      cert_file.close!
    end

    it 'leaves ica-pool in place when the classifier pin fails, so the pool is only cleared after a successful pin' do
      bootstrap_cfg.write("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      bootstrap_cfg.rewind
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind

      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => own_cert_pem }.to_json)
      allow(https).to receive(:get).and_return(cert_response)

      cert_file = Tempfile.new('ica.pem')
      allow(task).to receive(:ica_cert_path).and_return(cert_file.path) # rubocop:disable RSpec/SubjectStub
      allow(IcaTaskHelper).to receive(:pin_to_ica_group!).and_raise('classifier unavailable')

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }

      expect(File.read(ca_conf.path)).to include('ica-pool')
      expect(File.read(bootstrap_cfg.path)).to include('certificate-authority-disabled-service')
      cert_file.close!
    end

    it "refuses to install a certificate issued for a different node's identity" do
      bootstrap_cfg.write("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      bootstrap_cfg.rewind
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind

      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      wrong_node_cert = build_cert_pem('compiler-b.example.com')
      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => wrong_node_cert }.to_json)
      allow(https).to receive(:get).and_return(cert_response)
      expect(IcaTaskHelper).not_to receive(:pin_to_ica_group!)
      expect(Open3).not_to receive(:capture2e)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/install_ica_cert_failed')
        expect(parsed['_error']['msg']).to include('compiler-b.example.com')
        expect(parsed['_error']['msg']).to include('does not belong to this compiler')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(File.read(bootstrap_cfg.path)).to include('certificate-authority-disabled-service')
      expect(File.read(ca_conf.path)).to include('ica-pool')
    end

    it 'fails clearly when the primary returns something that does not parse as a certificate at all' do
      bootstrap_cfg.write("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      bootstrap_cfg.rewind

      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => 'not a certificate' }.to_json)
      allow(https).to receive(:get).and_return(cert_response)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/install_ica_cert_failed')
        expect(parsed['_error']['msg']).to include('Could not parse the certificate')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  describe '#clear_ica_pool!' do
    it 'removes a multi-line HOCON ica-pool array without leaving an orphaned array body' do
      ca_conf.write(<<~HOCON)
        certificate-authority: {
          ica-pool = [
            { url = "https://a.example.com:8140", weight = 3 },
            { url = "https://b.example.com:8140", weight = 1 }
          ]
        }
      HOCON
      ca_conf.rewind

      task.send(:clear_ica_pool!)

      content = File.read(ca_conf.path)
      expect(content).not_to include('ica-pool')
      expect(content).not_to include('weight')
      expect(content).not_to include(']')
    end

    it 'removes the colon-assignment form of ica-pool' do
      ca_conf.write(%(certificate-authority: {\n  ica-pool: ["https://x.example.com:8140"]\n}\n))
      ca_conf.rewind

      task.send(:clear_ica_pool!)

      expect(File.read(ca_conf.path)).not_to include('ica-pool')
    end

    it 'removes ica-pool without complaint when unrelated brackets exist elsewhere in ca.conf' do
      ca_conf.write(<<~HOCON)
        # unrelated tracking note with [brackets] in it
        certificate-authority: {
          allow-subject-alt-names: true
          some-other-url: "https://[fe80::1]:8140"
          ica-pool = ["https://old.example.com:8140"]
        }
      HOCON
      ca_conf.rewind

      expect { task.send(:clear_ica_pool!) }.not_to raise_error

      content = File.read(ca_conf.path)
      expect(content).not_to include('ica-pool')
      expect(content).not_to include('old.example.com')
      expect(content).to include('# unrelated tracking note with [brackets] in it')
      expect(content).to include('some-other-url: "https://[fe80::1]:8140"')
    end

    it 'correctly removes ica-pool when its value contains an IPv6 literal inside a quoted URL' do
      ca_conf.write(%(certificate-authority: {\n  ica-pool = ["https://[fe80::1]:8140"]\n}\n))
      ca_conf.rewind

      task.send(:clear_ica_pool!)

      content = File.read(ca_conf.path)
      expect(content).not_to include('ica-pool')
      expect(content).not_to include('fe80')
      expect(content).to eq("certificate-authority: {\n}\n")
    end

    it 'does not mistake a literal "]" inside a quoted value for the end of the array' do
      # A naive non-greedy match up to the first ']' would stop mid-value here,
      # leaving `suffix", "https://b.example"]` written into ca.conf verbatim.
      ca_conf.write(%(certificate-authority: {\n  ica-pool = ["https://a.example/path]suffix", "https://b.example"]\n}\n))
      ca_conf.rewind

      task.send(:clear_ica_pool!)

      content = File.read(ca_conf.path)
      expect(content).not_to include('ica-pool')
      expect(content).not_to include('suffix')
      expect(content).not_to include('a.example')
      expect(content).not_to include('b.example')
      expect(content).to eq("certificate-authority: {\n}\n")
    end

    it 'removes every ica-pool entry when more than one is present' do
      ca_conf.write(<<~HOCON)
        certificate-authority: {
          ica-pool = ["https://old-a.example.com:8140"]
        }
        certificate-authority-legacy: {
          ica-pool = ["https://old-b.example.com:8140"]
        }
      HOCON
      ca_conf.rewind

      task.send(:clear_ica_pool!)

      content = File.read(ca_conf.path)
      expect(content).not_to include('ica-pool')
      expect(content).not_to include('old-a.example.com')
      expect(content).not_to include('old-b.example.com')
    end

    it 'does not treat an escaped quote as closing the string, so a "]" right after it still counts as inside the value' do
      ca_conf.write(<<~'HOCON')
        certificate-authority: {
          ica-pool = ["https://example.com/a\"b]c", "https://other.example.com"]
        }
      HOCON
      ca_conf.rewind

      task.send(:clear_ica_pool!)

      content = File.read(ca_conf.path)
      expect(content).not_to include('ica-pool')
      expect(content).not_to include('example.com')
      expect(content).to eq("certificate-authority: {\n}\n")
    end

    it 'refuses to write when the array has no closing bracket at all (truncated or malformed file)' do
      original = %(certificate-authority: {\n  ica-pool = ["https://old.example.com:8140"\n}\n)
      ca_conf.write(original)
      ca_conf.rewind

      expect { task.send(:clear_ica_pool!) }.to raise_error(%r{Could not find a closing bracket for ica-pool})
      expect(File.read(ca_conf.path)).to eq(original)
    end
  end

  describe '#swap_bootstrap_cfg!' do
    it 'appends the intermediate-ca-service entry on its own line even when the last line has no trailing newline' do
      bootstrap_cfg.write(
        "puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n" \
        'puppetlabs.trapperkeeper.filesystem-watcher/filesystem-watcher-service',
      )
      bootstrap_cfg.rewind

      task.send(:swap_bootstrap_cfg!)

      lines = File.read(bootstrap_cfg.path).split("\n")
      expect(lines).to eq(
        [
          'puppetlabs.trapperkeeper.filesystem-watcher/filesystem-watcher-service',
          'puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service',
        ],
      )
    end

    it 'does not treat a commented-out intermediate-ca-service line as already promoted' do
      bootstrap_cfg.write(
        "# puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n" \
        "puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n",
      )
      bootstrap_cfg.rewind

      task.send(:swap_bootstrap_cfg!)

      lines = File.read(bootstrap_cfg.path).split("\n")
      expect(lines).to eq(
        [
          '# puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service',
          'puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service',
        ],
      )
    end

    it 'is a no-op on a bootstrap.cfg already swapped to intermediate-ca-service' do
      original = "puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service\n"
      bootstrap_cfg.write(original)
      bootstrap_cfg.rewind

      task.send(:swap_bootstrap_cfg!)

      expect(File.read(bootstrap_cfg.path)).to eq(original)
    end

    it 'keeps a commented-out disabled-service line and still refuses to modify the file' do
      original = "# puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n"
      bootstrap_cfg.write(original)
      bootstrap_cfg.rewind

      expect { task.send(:swap_bootstrap_cfg!) }.to raise_error(%r{refusing to modify it})
      expect(File.read(bootstrap_cfg.path)).to eq(original)
    end

    it 'refuses to modify a bootstrap.cfg that has neither a CA-proxy nor an intermediate CA service entry' do
      original = "puppetlabs.services.ca.certificate-authority-service/certificate-authority-service\n"
      bootstrap_cfg.write(original)
      bootstrap_cfg.rewind

      expect { task.send(:swap_bootstrap_cfg!) }
        .to raise_error(%r{shows neither a CA-proxy nor an intermediate CA service entry.*refusing to modify it})
      expect(File.read(bootstrap_cfg.path)).to eq(original)
    end
  end

  context 'when run against a node that is neither a CA-proxy nor an ICA compiler' do
    it 'fails before touching any local state or contacting the primary' do
      original = "puppetlabs.services.ca.certificate-authority-service/certificate-authority-service\n"
      bootstrap_cfg.write(original)
      bootstrap_cfg.rewind
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind

      expect(https).not_to receive(:get)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/install_ica_cert_failed')
        expect(parsed['_error']['msg']).to match(%r{refusing to modify it})
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(File.read(bootstrap_cfg.path)).to eq(original)
      expect(File.read(ca_conf.path)).to include('ica-pool')
    end
  end

  context 'when no active ICA exists yet on the primary (approval still pending or not yet approved)' do
    it 'fails the task without touching local state' do
      bootstrap_cfg.write("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      bootstrap_cfg.rewind
      not_found = instance_double('Net::HTTPResponse', code: '404', body: '')
      expect(https).to receive(:get).and_return(not_found)

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(File.read(bootstrap_cfg.path)).to include('certificate-authority-disabled-service')
    end
  end
end
