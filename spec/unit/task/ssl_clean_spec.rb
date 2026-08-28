require 'spec_helper'
require_relative '../../../tasks/ssl_clean'

describe SslClean do
  subject(:ssl_clean) { described_class.new(params) }

  let(:params) { { 'certname' => 'agent.example.com' } }
  let(:success_status) { instance_double('Process::Status', success?: true) }
  let(:failure_status) { instance_double('Process::Status', success?: false) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
  end

  context 'on Puppet < 6' do
    before(:each) do
      allow(Puppet).to receive(:version).and_return('5.5.10')
    end

    # Catches a mutation that drops the glob-delete branch (or deletes the
    # wrong files) on pre-Puppet-6, where `puppet ssl clean` doesn't exist
    # and manual file cleanup is required instead.
    it 'deletes matching ssl pem files directly and exits 0, without invoking `puppet ssl clean`' do
      matches = [
        '/etc/puppetlabs/puppet/ssl/certs/agent.example.com.pem',
        '/etc/puppetlabs/puppet/ssl/private_keys/agent.example.com.pem',
      ]
      allow(Dir).to receive(:glob).with('/etc/puppetlabs/puppet/ssl/**/agent.example.com.pem').and_return(matches)
      expect(File).to receive(:delete).with(matches[0])
      expect(File).to receive(:delete).with(matches[1])
      expect(Open3).not_to receive(:capture2)

      expect { ssl_clean.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end
  end

  context 'on Puppet >= 6' do
    before(:each) do
      allow(Puppet).to receive(:version).and_return('6.6.0')
    end

    # Catches a mutation that drops `--certname` or passes the wrong value,
    # which would clean the wrong node's SSL state (or none at all).
    it 'runs `puppet ssl clean --certname <name>` and exits 0 on success' do
      expect(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppet', 'ssl', 'clean',
                                                '--certname', 'agent.example.com')
                                          .and_return(['done', success_status])
      expect(Dir).not_to receive(:glob)

      expect { ssl_clean.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    # Catches a mutation that drops or inverts the `status.success?` check,
    # which would report success even when `puppet ssl clean` failed.
    it 'exits 1 when `puppet ssl clean` fails' do
      allow(Open3).to receive(:capture2).and_return(['error', failure_status])

      expect { ssl_clean.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end
end
