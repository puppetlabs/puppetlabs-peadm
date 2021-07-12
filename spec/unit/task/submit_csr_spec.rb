require 'spec_helper'
require_relative '../../../tasks/submit_csr'

describe SubmitCSR do
  subject(:submit_csr) { described_class.new(params) }

  let(:params) { {} }
  let(:status_dbl) { instance_double('Process::Status', success?: true) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(dns_alt_names: 'default,settings',
                                                   hostcert: '/not/a/real/file/test.pem',
                                                   certname: 'test')
  end

  context 'on Puppet 5' do
    before(:each) do
      expect(Puppet).to receive(:version).and_return('5.5.0')
    end

    it 'runs `puppet certificate generate`' do
      expect(Open3).to receive(:capture2e).with('/opt/puppetlabs/bin/puppet', 'certificate', any_args) { |*args|
        expect(args).to include('--dns-alt-names', 'default,settings')
      }.and_return(['output', status_dbl])

      expect { submit_csr.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end
  end

  context 'on Puppet 6' do
    before(:each) do
      expect(Puppet).to receive(:version).and_return('6.6.0')
      allow(Open3).to receive(:capture2e).with('/opt/puppetlabs/bin/puppet', 'ssl', 'verify')
                                         .and_return(['ssl-verify', instance_double('Process::Status', success?: false)])
    end

    it 'runs `puppet ssl submit_request' do
      expect(Open3).to receive(:capture2e).with('/opt/puppetlabs/bin/puppet', 'ssl', 'submit_request', any_args) { |*args|
        expect(args).not_to include('--dns_alt_names')
      }.and_return(['output', status_dbl])

      expect { submit_csr.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    describe 'with DNS alt names' do
      let(:params) { { 'dns_alt_names' => ['one', 'two', 'three'] } }

      it 'passes dns_alt_names when supplied' do
        expect(Open3).to receive(:capture2e).with('/opt/puppetlabs/bin/puppet', 'ssl', 'submit_request', any_args) { |*args|
          expect(args).to include('--dns_alt_names', 'one,two,three')
        }.and_return(['output', status_dbl])

        expect { submit_csr.execute! }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(0)
        end
      end
    end
  end
end
