require 'spec_helper'
require_relative '../../../tasks/submit_ica_csr'

describe SubmitIcaCsr do
  subject(:task) { described_class.new({}) }

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(Puppet).to receive(:settings).and_return(confdir: '/etc/puppetlabs/puppetserver')
  end

  context 'when the compiler is already promoted' do
    it 'is a no-op and exits 0' do
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(true)
      expect(IcaTaskHelper).not_to receive(:run_ica_provision)
      expect(STDOUT).to receive(:puts).with(JSON.generate('already-promoted' => true))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the subcommand succeeds' do
    it 'parses and returns the request-id, performing no cryptography itself' do
      status_dbl = instance_double('Process::Status', success?: true)
      allow(IcaTaskHelper).to receive_messages(
        promoted_to_ica?: false,
        run_ica_provision: ['{"request-id":"abc-123"}', '', status_dbl],
      )
      expect(STDOUT).to receive(:puts).with(JSON.generate('request-id' => 'abc-123'))

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'when the subcommand succeeds but writes to stderr' do
    # The subcommand owns spec section 18.5's trust bundle check, which warns
    # on a *successful* provision. Nothing else surfaces stderr on this path.
    it 'surfaces the subcommand stderr and still returns the request-id' do
      status_dbl = instance_double('Process::Status', success?: true)
      allow(IcaTaskHelper).to receive_messages(
        promoted_to_ica?: false,
        run_ica_provision: ['{"request-id":"abc-123"}',
                            'WARNING: ca.pem does not contain the root CA', status_dbl],
      )
      expect(STDOUT).to receive(:puts).with(JSON.generate('request-id' => 'abc-123'))

      expect {
        begin
          task.execute!
        rescue SystemExit => e
          expect(e.status).to eq(0)
        end
      }.to output(%r{ca\.pem does not contain the root CA}).to_stderr
    end

    it 'still surfaces stderr when the subcommand exits 0 with unparseable stdout' do
      status_dbl = instance_double('Process::Status', success?: true)
      allow(IcaTaskHelper).to receive_messages(
        promoted_to_ica?: false,
        run_ica_provision: ['not json', 'WARNING: something the operator should see', status_dbl],
      )

      expect {
        begin
          task.execute!
        rescue SystemExit => e
          expect(e.status).to eq(1)
        end
      }.to output(%r{something the operator should see}).to_stderr
    end
  end

  context 'when the subcommand succeeds quietly' do
    it 'emits nothing on stderr' do
      status_dbl = instance_double('Process::Status', success?: true)
      allow(IcaTaskHelper).to receive_messages(
        promoted_to_ica?: false,
        run_ica_provision: ['{"request-id":"abc-123"}', '', status_dbl],
      )

      expect {
        begin
          task.execute!
        rescue SystemExit => e
          expect(e.status).to eq(0)
        end
      }.not_to output.to_stderr
    end
  end

  context 'when the subcommand fails' do
    it 'surfaces the subcommand stderr and exits 1' do
      status_dbl = instance_double('Process::Status', success?: false)
      error_msg = 'ICA CSR submission failed: primary rejected CSR: 422 csr-validation-failed'
      allow(IcaTaskHelper).to receive_messages(
        promoted_to_ica?: false,
        run_ica_provision: ['', 'primary rejected CSR: 422 csr-validation-failed', status_dbl],
      )
      allow($stderr).to receive(:write)
      expect(STDOUT).to receive(:puts).with(
        JSON.generate('_error' => { 'msg' => error_msg, 'kind' => 'peadm/submit_ica_csr_failed' }),
      )

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the subcommand succeeds with malformed JSON' do
    it 'surfaces the parse error and exits 1' do
      status_dbl = instance_double('Process::Status', success?: true)
      allow(IcaTaskHelper).to receive_messages(
        promoted_to_ica?: false,
        run_ica_provision: ['not json', '', status_dbl],
      )
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/submit_ica_csr_failed')
        expect(parsed['_error']['msg']).to include('invalid subcommand response')
        expect(parsed['_error']['msg']).to include('not json')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the subcommand binary or verb does not exist' do
    it 'reports the failure through the _error contract instead of an uncaught exception' do
      allow(IcaTaskHelper).to receive(:promoted_to_ica?).and_return(false)
      allow(IcaTaskHelper).to receive(:run_ica_provision)
        .and_raise(Errno::ENOENT, 'No such file or directory - /opt/puppetlabs/bin/puppetserver')
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/submit_ica_csr_failed')
        expect(parsed['_error']['msg']).to include('/opt/puppetlabs/bin/puppetserver')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the subcommand succeeds with valid JSON missing request-id' do
    it 'surfaces the key error and exits 1' do
      status_dbl = instance_double('Process::Status', success?: true)
      allow(IcaTaskHelper).to receive_messages(
        promoted_to_ica?: false,
        run_ica_provision: ['{}', '', status_dbl],
      )
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/submit_ica_csr_failed')
        expect(parsed['_error']['msg']).to include('invalid subcommand response')
        expect(parsed['_error']['msg']).to include('{}')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
