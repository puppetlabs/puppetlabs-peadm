# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../../tasks/prepare_ica_promotion'

describe PrepareIcaPromotion do
  subject(:task) { described_class.new('primary_host' => 'primary.example.com') }

  let(:classifier_https) { instance_double('Net::HTTP') }
  let(:ca_conf) { Tempfile.new('ca.conf') }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(certname: 'compiler-a.example.com', confdir: '/etc/puppetlabs/puppetserver')
    allow(IcaTaskHelper).to receive(:ca_conf_path).and_return(ca_conf.path)
    allow(IcaTaskHelper).to receive(:primary_https_client).with('primary.example.com', IcaTaskHelper::CLASSIFIER_PORT).and_return(classifier_https)
    allow(IcaTaskHelper).to receive(:pin_to_ica_group!)
  end

  after(:each) do
    ca_conf.close!
  end

  describe '#execute!' do
    it 'pins the classifier group, clears ica-pool, and reports pinned' do
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind
      expect(IcaTaskHelper).to receive(:pin_to_ica_group!).with(classifier_https, 'compiler-a.example.com')
      expect(STDOUT).to receive(:puts).with(JSON.generate('status' => 'pinned'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }

      expect(File.read(ca_conf.path)).not_to include('ica-pool')
    end

    it 'pins before clearing ica-pool, and leaves ica-pool in place if the pin fails' do
      ca_conf.write("certificate-authority {\n  ica-pool = [\"https://old.example.com:8140\"]\n}\n")
      ca_conf.rewind
      allow(IcaTaskHelper).to receive(:pin_to_ica_group!).and_raise('classifier unavailable')
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/prepare_ica_promotion_failed')
        expect(parsed['_error']['msg']).to eq('classifier unavailable')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }

      expect(File.read(ca_conf.path)).to include('ica-pool')
    end

    it 'logs the exception class and a backtrace to stderr on an unexpected failure' do
      allow(IcaTaskHelper).to receive(:pin_to_ica_group!).and_raise(StandardError, 'boom')

      expect {
        begin
          task.execute!
        rescue SystemExit => e
          expect(e.status).to eq(1)
        end
      }.to output(%r{StandardError: boom}).to_stderr
    end

    it 'fails clearly, without a raw backtrace on stdout, when clearing ica-pool finds no closing bracket' do
      ca_conf.write('certificate-authority: { ica-pool = ["https://old.example.com:8140"')
      ca_conf.rewind

      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/prepare_ica_promotion_failed')
        expect(parsed['_error']['msg']).to include('Could not find a closing bracket for ica-pool')
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

    it 'refuses to write when the array has no closing bracket at all (truncated or malformed file)' do
      original = %(certificate-authority: {\n  ica-pool = ["https://old.example.com:8140"\n}\n)
      ca_conf.write(original)
      ca_conf.rewind

      expect { task.send(:clear_ica_pool!) }.to raise_error(%r{Could not find a closing bracket for ica-pool})
      expect(File.read(ca_conf.path)).to eq(original)
    end
  end
end
