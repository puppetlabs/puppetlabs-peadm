require 'spec_helper'
require_relative '../../../tasks/sign_csr'

describe SignCSR do
  subject(:sign_csr) { described_class.new(params) }

  let(:params) { { 'certnames' => certnames } }
  let(:certnames) { ['agent.example.com'] }
  let(:success_status) { instance_double('Process::Status', success?: true) }
  let(:failure_status) { instance_double('Process::Status', success?: false) }

  before(:each) do
    allow(Puppet).to receive(:initialize_settings)
    allow(Puppet).to receive(:settings).and_return(csrdir: '/etc/puppetlabs/puppet/ssl/ca/requests',
                                                    cadir: '/etc/puppetlabs/puppet/ssl/ca')
    allow(STDOUT).to receive(:puts)
  end

  describe '#csr_signed?' do
    let(:csr_path) { '/etc/puppetlabs/puppet/ssl/ca/requests/agent.example.com.pem' }
    let(:signed_path) { '/etc/puppetlabs/puppet/ssl/ca/signed/agent.example.com.pem' }

    # Catches a mutation that inverts or drops either half of the
    # File.exist? check, which would cause an already-signed cert to be
    # (re)submitted for signing again.
    it 'is true when the CSR is no longer pending and a signed cert exists' do
      allow(File).to receive(:exist?).with(csr_path).and_return(false)
      allow(File).to receive(:exist?).with(signed_path).and_return(true)
      expect(sign_csr.csr_signed?('agent.example.com')).to eq(true)
    end

    it 'is false when the CSR is still pending, even if a signed cert exists' do
      allow(File).to receive(:exist?).with(csr_path).and_return(true)
      allow(File).to receive(:exist?).with(signed_path).and_return(true)
      expect(sign_csr.csr_signed?('agent.example.com')).to eq(false)
    end

    it 'is false when no signed cert exists yet' do
      allow(File).to receive(:exist?).with(csr_path).and_return(false)
      allow(File).to receive(:exist?).with(signed_path).and_return(false)
      expect(sign_csr.csr_signed?('agent.example.com')).to eq(false)
    end
  end

  describe '#sign' do
    it 'does not raise when the puppetserver ca sign command succeeds' do
      expect(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
                                                '--certname', 'agent.example.com')
                                         .and_return(['ok', success_status])
      expect { sign_csr.sign(['agent.example.com']) }.not_to raise_error
    end

    # Catches a mutation that drops or inverts the `unless status.success?`
    # guard (which would make `sign` raise nothing at all on failure).
    # `SigningError` inherits from `StandardError` (PE-46427) so this is the
    # exception `#execute!`'s retry loop actually catches; previously it
    # inherited from nothing, `raise SigningError` raised a bare `TypeError`
    # instead, and the retry loop below could never enter its rescue clause.
    it 'raises SigningError when the sign command fails' do
      allow(Open3).to receive(:capture2).and_return(['failed', failure_status])
      expect { sign_csr.sign(['agent.example.com']) }.to raise_error(SignCSR::SigningError)
    end
  end

  describe '#execute!' do
    # Catches a mutation that signs (or attempts to sign) certs that are
    # already fully signed, which could cause unnecessary cert churn.
    it 'excludes already-signed certnames from the sign call' do
      params_dbl = { 'certnames' => ['already-signed.example.com', 'still-pending.example.com'] }
      task = described_class.new(params_dbl)
      allow(task).to receive(:puts)
      allow(task).to receive(:csr_signed?).with('already-signed.example.com').and_return(true)
      allow(task).to receive(:csr_signed?).with('still-pending.example.com').and_return(false)

      expect(Open3).to receive(:capture2).with('/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
                                                '--certname', 'still-pending.example.com')
                                         .and_return(['ok', success_status])

      task.execute!
    end

    # Catches a mutation that removes/breaks the `unsigned.empty?` early
    # exit, which would otherwise invoke `sign` with an empty certname list.
    it 'exits 0 without attempting to sign anything when all certs are already signed' do
      # A fresh instance (not the shared `subject`) so csr_signed? can be
      # stubbed without RuboCop flagging a self-stub on the object under
      # test -- this is otherwise the exact same construction as `subject`.
      task = described_class.new(params)
      allow(task).to receive(:csr_signed?).and_return(true)
      expect(Open3).not_to receive(:capture2)

      expect { task.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    # Catches a mutation to the retry bound (e.g. `attempts > 5` -> `attempts
    # > 4`) that would cause the task to give up too early even though the
    # cert eventually became signed. Exercises the real retry path now that
    # `SigningError` is a `StandardError` (PE-46427): a transient failure
    # (e.g. a CSR not yet visible due to replication lag) is retried, with a
    # 1s sleep between attempts, rather than crashing on the first failure.
    it 'retries a failed sign attempt and succeeds once the command eventually succeeds' do
      task = described_class.new(params)
      allow(task).to receive(:csr_signed?).and_return(false)
      expect(task).to receive(:sleep).with(1).twice

      call_count = 0
      allow(Open3).to receive(:capture2) do
        call_count += 1
        if call_count < 3
          ['failed', failure_status]
        else
          ['ok', success_status]
        end
      end

      expect { task.execute! }.not_to raise_error
      expect(call_count).to eq(3)
    end

    # Catches a mutation that widens, narrows, or removes the retry bound,
    # which would make the task retry forever, give up too early, or too
    # late instead of exiting 1 after a bounded number of failed attempts.
    it 'exits 1 after exhausting all retries on a sign command that always fails' do
      task = described_class.new(params)
      allow(task).to receive(:csr_signed?).and_return(false)
      expect(task).to receive(:sleep).with(1).exactly(6).times

      call_count = 0
      allow(Open3).to receive(:capture2) do
        call_count += 1
        ['failed', failure_status]
      end

      expect { task.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
      expect(call_count).to eq(7)
    end
  end
end
