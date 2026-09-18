require 'spec_helper'
require_relative '../../../tasks/sign_csr'

describe SignCSR do
  subject(:sign_csr) { described_class.new(params) }

  let(:params) { { 'certnames' => certnames } }
  let(:certnames) { ['agent.example.com'] }
  let(:success_status) { instance_double('Process::Status', success?: true) }
  let(:failure_status) { instance_double('Process::Status', success?: false, exitstatus: 1) }

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
      expect(Open3).to receive(:capture2e).with('/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
                                                 '--certname', 'agent.example.com')
                                          .and_return(['ok', success_status])
      expect { sign_csr.sign(['agent.example.com']) }.not_to raise_error
    end

    # Catches a mutation that drops or inverts the `return if status.success?`
    # guard (which would make `sign` raise on success or swallow a failure).
    # `SigningError` inherits from `StandardError` (PE-46427) so this is the
    # exception `#execute!`'s retry loop actually catches; previously it
    # inherited from nothing, `raise SigningError` raised a bare `TypeError`
    # instead, and the retry loop below could never enter its rescue clause.
    # The message carries the exit status and captured output (stdout+stderr,
    # merged via capture2e) so a final "giving up" log actually says why.
    # Uses a distinct exit code (2, not the shared failure_status's 1) so a
    # mutation hardcoding the exit code in the message would still be caught.
    it 'raises SigningError with the exit status and output when the sign command fails' do
      distinct_exit_status = instance_double('Process::Status', success?: false, exitstatus: 2)
      allow(Open3).to receive(:capture2e).and_return(['some error output', distinct_exit_status])
      expect { sign_csr.sign(['agent.example.com']) }
        .to raise_error(SignCSR::SigningError, 'puppetserver ca sign exited 2: some error output')
    end

    # Catches a mutation that drops the newline-collapsing before the output
    # is embedded in SigningError's message. capture2e can return multi-line
    # output (e.g. a Java stack trace); without collapsing it, the per-retry
    # and give-up log lines that embed this message would themselves become
    # multi-line and stop being a single grep-able line per attempt. Leading
    # and trailing newlines are included so a mutation dropping `.strip`
    # (leaving stray leading/trailing spaces after the collapse) is also
    # caught, not just a mutation dropping `gsub` entirely.
    it 'collapses multi-line command output to a single line in the error message' do
      output = "\n  line one\n  line two\nline three\n"
      allow(Open3).to receive(:capture2e).and_return([output, failure_status])
      expect { sign_csr.sign(['agent.example.com']) }
        .to raise_error(SignCSR::SigningError, 'puppetserver ca sign exited 1: line one line two line three')
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

      expect(Open3).to receive(:capture2e).with('/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
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
      expect(Open3).not_to receive(:capture2e)

      expect { task.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(0)
      end
    end

    # Catches a mutation to the retry bound (e.g. `attempts > 6` -> `attempts
    # > 5`) that would cause the task to give up too early even though the
    # cert eventually became signed. Exercises the real retry path now that
    # `SigningError` is a `StandardError` (PE-46427): a transient failure
    # (e.g. a CSR not yet visible due to replication lag) is retried, with a
    # 1s sleep between attempts, rather than crashing on the first failure.
    it 'retries a failed sign attempt and succeeds once the command eventually succeeds' do
      task = described_class.new(params)
      allow(task).to receive(:csr_signed?).and_return(false)
      expect(task).to receive(:sleep).with(1).twice
      expect(Open3).to receive(:capture2e).exactly(3).times
                                          .and_return(['failed', failure_status],
                                                       ['failed', failure_status],
                                                       ['ok', success_status])
      # Pins the retry log line to include the failure's cause, not just an
      # attempt number -- a mutation that drops `(#{e.message})` would
      # otherwise go uncaught, since STDOUT.puts is stubbed unconditionally
      # in before(:each).
      expect(STDOUT).to receive(:puts)
        .with('Signing attempt 1 failed (puppetserver ca sign exited 1: failed); waiting 1s and trying again')

      expect { task.execute! }.not_to raise_error
    end

    # Catches a mutation that widens, narrows, or removes the retry bound,
    # which would make the task retry forever, give up too early, or too
    # late instead of exiting 1 after a bounded number of failed attempts.
    # Also catches a mutation that drops the final "giving up" message,
    # which is the only diagnostic an operator gets once retries run out.
    it 'exits 1 after exhausting all retries on a sign command that always fails' do
      task = described_class.new(params)
      allow(task).to receive(:csr_signed?).and_return(false)
      expect(task).to receive(:sleep).with(1).exactly(6).times
      expect(Open3).to receive(:capture2e).exactly(7).times.and_return(['failed', failure_status])
      # Full-string match, not just an anchor-free substring, so a mutation
      # that drops the `: #{e.message}` suffix (the actual failure cause)
      # would still be caught here.
      expect(task).to receive(:warn)
        .with('Signing failed after 7 attempts, giving up: puppetserver ca sign exited 1: failed')

      expect { task.execute! }.to raise_error(SystemExit) do |error|
        expect(error.status).to eq(1)
      end
    end
  end
end
