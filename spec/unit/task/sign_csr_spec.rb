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

    # DOCUMENTS AN EXISTING BUG (not fixed here; tasks/sign_csr.rb is out of
    # scope for this ticket). `SigningError` is defined as
    # `class SigningError; end` with no Exception/StandardError superclass,
    # so `raise SigningError` never actually raises a SigningError: Ruby's
    # `raise` immediately raises `TypeError: exception class/object expected`
    # instead, because the given class isn't Exception-like. This test pins
    # that real, current behavior so it still catches a mutation that drops
    # or inverts the `unless status.success?` guard (which would make `sign`
    # raise nothing at all on failure). If `SigningError` is ever corrected
    # to `< StandardError`, this test must be updated to expect
    # `SignCSR::SigningError` instead of `TypeError`, and the two `#execute!`
    # retry-loop tests below should be revisited, since the `rescue
    # SigningError` clause in `execute!` currently can never be entered.
    it 'raises TypeError (not the intended SigningError) when the sign command fails' do
      allow(Open3).to receive(:capture2).and_return(['failed', failure_status])
      expect { sign_csr.sign(['agent.example.com']) }.to raise_error(TypeError, 'exception class/object expected')
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
    # cert eventually became signed.
    #
    # NOTE: because of the `SigningError` bug documented above (it isn't a
    # StandardError, so `raise SigningError` in `#sign` raises a bare
    # TypeError that `rescue SigningError` cannot catch), the retry branch in
    # `execute!` is currently unreachable dead code: the very first failed
    # sign attempt propagates an uncaught TypeError instead of being
    # rescued and retried. This test pins that real, current behavior
    # (rather than asserting a retry-then-`exit 0` sequence that cannot
    # actually happen against the unmodified task file) so it still fails if
    # a mutation changes what "signing fails" looks like.
    it 'propagates an uncaught TypeError on the first failed sign attempt, never reaching the retry/exit-0 path' do
      task = described_class.new(params)
      allow(task).to receive(:csr_signed?).and_return(false)
      expect(task).not_to receive(:sleep)
      allow(Open3).to receive(:capture2).and_return(['failed', failure_status])

      expect { task.execute! }.to raise_error(TypeError, 'exception class/object expected')
    end

    # Same root cause as above: the retry-exhaustion path (`exit 1` after 6
    # failed attempts) is dead code today because `rescue SigningError` never
    # matches the TypeError that `#sign` actually raises. This test pins
    # that exactly one sign attempt is made (not 7) and that no SystemExit
    # is ever raised, so it still catches a mutation that changed how many
    # times `Open3.capture2` is invoked before the (currently unreachable)
    # retry/exit-1 logic would kick in.
    it 'does not retry or exit 1 after a failed sign attempt, because the retry rescue is unreachable' do
      task = described_class.new(params)
      allow(task).to receive(:csr_signed?).and_return(false)
      expect(task).not_to receive(:sleep)

      call_count = 0
      allow(Open3).to receive(:capture2) do
        call_count += 1
        ['failed', failure_status]
      end

      expect { task.execute! }.to raise_error(TypeError)
      expect(call_count).to eq(1)
    end
  end
end
