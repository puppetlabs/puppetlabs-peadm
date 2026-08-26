# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../../tasks/install_ica_cert'

describe InstallIcaCert do
  subject(:task) { described_class.new('primary_host' => 'primary.example.com') }

  let(:https) { instance_double('Net::HTTP') }
  let(:classifier_https) { instance_double('Net::HTTP') }
  let(:bootstrap_cfg) { Tempfile.new('bootstrap.cfg') }
  let(:ca_conf) { Tempfile.new('ca.conf') }

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

  context 'when already installed' do
    it 'is a no-op and exits 0' do
      bootstrap_cfg.write('puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service')
      bootstrap_cfg.rewind
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(true)
      expect(https).not_to receive(:get)
      expect(STDOUT).to receive(:puts).with(JSON.generate('status' => 'already-installed'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    it 'still re-attempts the CA reload and fails the task when that reload fails' do
      bootstrap_cfg.write('puppetlabs.services.ca.intermediate-ca-service/intermediate-ca-service')
      bootstrap_cfg.rewind
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(true)
      expect(Open3).to receive(:capture2e)
        .with(IcaTaskHelper::PUPPETSERVER_BIN, 'ca', 'reload')
        .and_return(['reload refused', instance_double('Process::Status', success?: false)])
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/install_ica_cert_failed')
        expect(parsed['_error']['msg']).to include('Failed to reload CA service')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when an active ICA is available on the primary' do
    it 'installs the cert, swaps bootstrap.cfg, clears ica-pool, pins the classifier group, and restarts the service' do
      bootstrap_cfg.write("puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n")
      bootstrap_cfg.rewind
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind

      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => 'CERT-PEM-DATA' }.to_json)
      expect(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca/compiler-a.example.com').and_return(cert_response)

      cert_file = Tempfile.new('ica.pem')
      allow(task).to receive(:ica_cert_path).and_return(cert_file.path) # rubocop:disable RSpec/SubjectStub

      expect(IcaTaskHelper).to receive(:pin_to_ica_group!).with(classifier_https, 'compiler-a.example.com')
      expect(Open3).to receive(:capture2e)
        .with('/opt/puppetlabs/bin/puppetserver', 'ca', 'reload')
        .and_return(['', instance_double('Process::Status', success?: true)])
      expect(STDOUT).to receive(:puts).with(JSON.generate('status' => 'installed'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }

      expect(File.read(cert_file.path)).to eq('CERT-PEM-DATA')
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
      cert_response = instance_double('Net::HTTPResponse', code: '200', body: { 'cert-pem' => 'CERT-PEM-DATA' }.to_json)
      allow(https).to receive(:get).and_return(cert_response)

      cert_file = Tempfile.new('ica.pem')
      allow(task).to receive(:ica_cert_path).and_return(cert_file.path) # rubocop:disable RSpec/SubjectStub
      allow(IcaTaskHelper).to receive(:pin_to_ica_group!).and_raise('classifier unavailable')

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }

      expect(File.read(ca_conf.path)).to include('ica-pool')
      expect(File.read(bootstrap_cfg.path)).to include('certificate-authority-disabled-service')
      cert_file.close!
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
        # see PEADM-123 [tracking] for why this is here
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
      expect(content).to include('# see PEADM-123 [tracking] for why this is here')
      expect(content).to include('some-other-url: "https://[fe80::1]:8140"')
    end

    it 'refuses to write when removal would leave unbalanced brackets (IPv6 literal in a quoted URL)' do
      original = %(certificate-authority: {\n  ica-pool = ["https://[fe80::1]:8140"]\n}\n)
      ca_conf.write(original)
      ca_conf.rewind

      expect { task.send(:clear_ica_pool!) }.to raise_error(%r{unbalanced brackets})
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

    it 'keeps a commented-out disabled-service line and still refuses the swap' do
      original = "# puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n"
      bootstrap_cfg.write(original)
      bootstrap_cfg.rewind

      expect { task.send(:swap_bootstrap_cfg!) }.to raise_error(%r{refusing to swap})
      expect(File.read(bootstrap_cfg.path)).to eq(original)
    end

    it 'refuses to swap a bootstrap.cfg that has no CA-proxy service entry' do
      original = "puppetlabs.services.ca.certificate-authority-service/certificate-authority-service\n"
      bootstrap_cfg.write(original)
      bootstrap_cfg.rewind

      expect { task.send(:swap_bootstrap_cfg!) }
        .to raise_error(%r{does not show the expected CA-proxy service entry.*refusing to swap})
      expect(File.read(bootstrap_cfg.path)).to eq(original)
    end
  end

  context 'when run against a node that is not a CA-proxy compiler' do
    it 'fails before touching any local state' do
      original = "puppetlabs.services.ca.certificate-authority-service/certificate-authority-service\n"
      bootstrap_cfg.write(original)
      bootstrap_cfg.rewind
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind

      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      expect(https).not_to receive(:get)
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/install_ica_cert_failed')
        expect(parsed['_error']['msg']).to match(%r{refusing to swap})
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
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      not_found = instance_double('Net::HTTPResponse', code: '404', body: '')
      expect(https).to receive(:get).and_return(not_found)

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      expect(File.read(bootstrap_cfg.path)).to include('certificate-authority-disabled-service')
    end
  end
end
