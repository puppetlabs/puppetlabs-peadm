require 'spec_helper'
require 'net/http'
require 'openssl'
require 'time'
require_relative '../../../tasks/check_ica_expiry'

describe CheckIcaExpiry do
  subject(:task) { described_class.new(params, https_client: https, now: now) }

  let(:now) { Time.utc(2026, 11, 1, 0, 0, 0) }
  let(:params) { {} }
  let(:icas) { [] }
  let(:https) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPResponse, code: '200', body: { 'intermediate-cas' => icas }.to_json) }

  def ica(fqdn, state, days_from_now)
    {
      'compiler-fqdn' => fqdn,
      'state' => state,
      'provisioned-at' => '2026-01-01T00:00:00Z',
      'not-after' => (now + (days_from_now * 86_400)).utc.iso8601,
    }
  end

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca').and_return(response)
  end

  def run_expecting_exit(status)
    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(status) }
  end

  context 'with an ICA in the 90 day band only' do
    let(:icas) { [ica('c1.example.com', 'active', 80)] }

    it 'reports it with days remaining and the matched band, and exits zero' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output.split("\n").last.split(%r{\s+})).to include('c1.example.com', 'active', '80', '90')
      end

      run_expecting_exit(0)
    end
  end

  context 'with an ICA in the 60 day band only' do
    let(:params) { { 'format' => 'json' } }
    let(:icas) { [ica('c1.example.com', 'active', 50)] }

    it 'reports the 60 day band and exits zero' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['icas'].first).to include('days-remaining' => 50, 'threshold-band' => 60)
      end

      run_expecting_exit(0)
    end
  end

  context 'with an ICA in the tightest (30 day) band' do
    let(:icas) { [ica('c1.example.com', 'draining', 10)] }

    it 'reports it and exits non-zero' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to include('c1.example.com', 'draining', '10', '30')
      end

      run_expecting_exit(1)
    end
  end

  context 'with an ICA that has already expired' do
    let(:icas) { [ica('c1.example.com', 'active', -3)] }

    it 'reports negative days remaining in the tightest band and exits non-zero' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to include('c1.example.com', '-3')
      end

      run_expecting_exit(1)
    end
  end

  context 'with only ICAs outside every band' do
    let(:icas) { [ica('c1.example.com', 'active', 200)] }

    it 'omits them from the report and exits zero' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).not_to include('c1.example.com')
        expect(output).to match(%r{no active or draining compiler ICAs expire within 90 days})
      end

      run_expecting_exit(0)
    end
  end

  context 'with revoked and decommissioned ICAs inside the tightest band' do
    let(:icas) do
      [ica('c1.example.com', 'revoked', 5), ica('c2.example.com', 'decommissioned', 5), ica('c3.example.com', 'active', 200)]
    end

    it 'excludes them and exits zero' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).not_to include('c1.example.com', 'c2.example.com')
      end

      run_expecting_exit(0)
    end
  end

  context 'with a mix of ICAs' do
    let(:icas) do
      [ica('c1.example.com', 'active', 85), ica('c2.example.com', 'active', 25), ica('c3.example.com', 'active', 400)]
    end

    it 'reports only those inside a band and exits non-zero because one is in the tightest' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to include('c1.example.com', 'c2.example.com')
        expect(output).not_to include('c3.example.com')
      end

      run_expecting_exit(1)
    end
  end

  context 'with no ICAs registered' do
    let(:icas) { [] }

    it 'exits zero with an explicit message' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to match(%r{no compiler ICAs are registered}i)
      end

      run_expecting_exit(0)
    end
  end

  context 'with custom thresholds' do
    let(:params) { { 'thresholds' => [14, 7] } }
    let(:icas) { [ica('c1.example.com', 'active', 20), ica('c2.example.com', 'active', 10)] }

    it 'honours them: 20 days is outside, 10 days is in the 14 day band, and the tightest is 7' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to include('c2.example.com')
        expect(output).not_to include('c1.example.com')
      end

      run_expecting_exit(0)
    end

    context 'with an ICA inside the custom tightest band' do
      let(:icas) { [ica('c1.example.com', 'active', 6)] }

      it 'exits non-zero' do
        run_expecting_exit(1)
      end
    end
  end

  context 'with unsorted custom thresholds' do
    let(:params) { { 'thresholds' => [7, 30, 14] } }
    let(:icas) { [ica('c1.example.com', 'active', 10)] }

    it 'treats the smallest as the tightest band regardless of order' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output.split("\n").last.split(%r{\s+}).last).to eq('14')
      end

      run_expecting_exit(0)
    end
  end

  context 'with an empty thresholds array' do
    let(:params) { { 'thresholds' => [] } }

    it 'fails with an actionable message' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['msg']).to match(%r{thresholds}i).and match(%r{at least one}i)
        expect(parsed['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_thresholds')
      end

      run_expecting_exit(2)
    end
  end

  context 'with non-numeric thresholds' do
    let(:params) { { 'thresholds' => [90, 'soon'] } }

    it 'fails naming the offending value' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(JSON.parse(output)['_error']['msg']).to include('soon')
      end

      run_expecting_exit(2)
    end
  end

  context 'with a non-positive threshold' do
    let(:params) { { 'thresholds' => [30, 0] } }

    it 'fails' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_thresholds')
      end

      run_expecting_exit(2)
    end
  end

  context 'with a thresholds value that is not an array' do
    let(:params) { { 'thresholds' => 30 } }

    it 'fails' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_thresholds')
      end

      run_expecting_exit(2)
    end
  end

  context "with format => 'json'" do
    let(:params) { { 'format' => 'json' } }
    let(:icas) { [ica('c1.example.com', 'active', 10), ica('c2.example.com', 'active', 500)] }

    it 'returns the matched ICAs, thresholds, and still exits non-zero in the tightest band' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['thresholds']).to eq([90, 60, 30])
        expect(parsed['icas'].map { |i| i['compiler-fqdn'] }).to eq(['c1.example.com'])
        expect(parsed['icas'].first).to include('days-remaining' => 10, 'threshold-band' => 30, 'state' => 'active')
      end

      run_expecting_exit(1)
    end
  end

  context "with format => 'json' and no ICAs registered" do
    let(:params) { { 'format' => 'json' } }

    it 'returns an empty list and exits zero' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(JSON.parse(output)['icas']).to eq([])
      end

      run_expecting_exit(0)
    end
  end

  context 'when the endpoint returns an HTTP error' do
    let(:response) { instance_double(Net::HTTPResponse, code: '403', body: 'forbidden') }

    it 'fails with a structured error' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['msg']).to include('403')
        expect(parsed['_error']['kind']).to eq('peadm/check_ica_expiry_failed')
      end

      run_expecting_exit(2)
    end
  end

  context 'when the response body is not valid' do
    let(:response) { instance_double(Net::HTTPResponse, code: '200', body: 'not json') }

    it 'fails with a structured error' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_response')
      end

      run_expecting_exit(2)
    end
  end

  context 'when an ICA has an unparseable not-after' do
    let(:icas) { [{ 'compiler-fqdn' => 'c1.example.com', 'state' => 'active', 'not-after' => 'garbage' }] }

    it 'fails with a structured error rather than silently skipping it' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_response')
        expect(parsed['_error']['msg']).to include('c1.example.com')
      end

      run_expecting_exit(2)
    end
  end

  context 'at the edges of each band' do
    {
      91 => nil, 90 => 90, 61 => 90, 60 => 60, 31 => 60, 30 => 30
    }.each do |days, band|
      context "with #{days} days remaining" do
        let(:params) { { 'format' => 'json' } }
        let(:icas) { [ica('c1.example.com', 'active', days)] }

        it "is #{band ? "in band #{band}" : 'outside every band'}" do
          expect(STDOUT).to receive(:puts) do |output|
            expect(JSON.parse(output)['icas'].map { |i| i['threshold-band'] }).to eq([band].compact)
          end

          run_expecting_exit((band == 30) ? 1 : 0)
        end
      end
    end
  end

  context 'with a fractional number of days remaining' do
    let(:params) { { 'format' => 'json' } }

    context 'just over 30 days' do
      let(:icas) { [ica('c1.example.com', 'active', 30).merge('not-after' => (now + (30 * 86_400) + 3600).utc.iso8601)] }

      it 'rounds down to 30 days and lands in the tightest band' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['icas'].first['days-remaining']).to eq(30) }

        run_expecting_exit(1)
      end
    end

    context 'one second short of 30 days' do
      let(:icas) { [ica('c1.example.com', 'active', 30).merge('not-after' => (now + (30 * 86_400) - 1).utc.iso8601)] }

      it 'reports 29 days' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['icas'].first['days-remaining']).to eq(29) }

        run_expecting_exit(1)
      end
    end
  end

  context 'with unsorted custom thresholds in json format' do
    let(:params) { { 'format' => 'json', 'thresholds' => [7, 30, 14, 30] } }

    it 'echoes them de-duplicated and sorted descending' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['thresholds']).to eq([30, 14, 7]) }

      run_expecting_exit(0)
    end
  end

  context 'with an unsupported format' do
    let(:params) { { 'format' => 'xml' } }

    it 'fails before contacting the primary' do
      expect(https).not_to receive(:get)
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_format') }

      run_expecting_exit(2)
    end
  end

  [[0], [-5], [30.5], ['30'], [nil], [true]].each do |bad|
    context "with thresholds #{bad.inspect}" do
      let(:params) { { 'thresholds' => bad } }

      it 'fails before contacting the primary, naming the offending value' do
        expect(https).not_to receive(:get)
        expect(STDOUT).to receive(:puts) do |output|
          parsed = JSON.parse(output)['_error']
          expect(parsed['kind']).to eq('peadm/check_ica_expiry_invalid_thresholds')
          expect(parsed['msg']).to include(bad.first.inspect)
        end

        run_expecting_exit(2)
      end
    end
  end

  context 'when the TLS handshake fails' do
    before(:each) { allow(https).to receive(:get).and_raise(OpenSSL::SSL::SSLError, 'bad cert') }

    it 'fails with a tls error' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_tls_failed') }

      run_expecting_exit(2)
    end
  end

  [Errno::ECONNREFUSED, Net::ReadTimeout, Net::OpenTimeout, Net::WriteTimeout, SocketError, EOFError, Net::HTTPBadResponse].each do |error_class|
    context "when the connection fails with #{error_class}" do
      before(:each) { allow(https).to receive(:get).and_raise(error_class) }

      it 'fails with a connection error' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_connection_failed') }

        run_expecting_exit(2)
      end
    end
  end

  context 'when the agent credentials cannot be loaded' do
    subject(:task) { described_class.new(params, now: now) }

    before(:each) do
      allow(Puppet.settings).to receive(:[]).and_call_original
      allow(Puppet.settings).to receive(:[]).with(:certname).and_return('primary.example.com')
      allow(Puppet.settings).to receive(:[]).with(:hostcert).and_return('/nonexistent/hostcert.pem')
      allow(Puppet.settings).to receive(:[]).with(:hostprivkey).and_return('/nonexistent/hostprivkey.pem')
    end

    it 'fails with a credential error' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_credential_error') }

      run_expecting_exit(2)
    end
  end

  [
    ['a missing intermediate-cas', {}],
    ['null intermediate-cas', { 'intermediate-cas' => nil }],
    ['a non-list intermediate-cas', { 'intermediate-cas' => { 'a' => 1 } }],
    ['a non-object entry', { 'intermediate-cas' => [nil] }],
  ].each do |label, body|
    context "when the response has #{label}" do
      let(:response) { instance_double(Net::HTTPResponse, code: '200', body: body.to_json) }

      it 'fails with a structured invalid-response error' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_response') }

        run_expecting_exit(2)
      end
    end
  end

  context 'when something unexpected is raised' do
    before(:each) { allow(https).to receive(:get).and_raise(RuntimeError, 'boom') }

    it 'still emits a structured error and the check-failed exit code' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_unexpected') }

      run_expecting_exit(2)
    end
  end

  context 'when the endpoint returns a very large error body' do
    let(:response) { instance_double(Net::HTTPResponse, code: '502', body: 'x' * 5000) }

    it 'truncates the body in the error message' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['msg'].length).to be < 700 }

      run_expecting_exit(2)
    end
  end

  it 'documents the same default thresholds as the code' do
    metadata = JSON.parse(File.read(File.expand_path('../../../tasks/check_ica_expiry.json', __dir__)))
    description = metadata['parameters']['thresholds']['description']
    expect(description).to include("Defaults to #{described_class::DEFAULT_THRESHOLDS.inspect}")
  end

  it 'declares thresholds as non-empty in the type itself and reads parameters from stdin' do
    metadata = JSON.parse(File.read(File.expand_path('../../../tasks/check_ica_expiry.json', __dir__)))
    expect(metadata['parameters']['thresholds']['type']).to eq('Optional[Array[Integer[1], 1]]')
    expect(metadata['input_method']).to eq('stdin')
  end

  it 'declares both parameters as optional so a bare task run is accepted' do
    metadata = JSON.parse(File.read(File.expand_path('../../../tasks/check_ica_expiry.json', __dir__)))
    expect(metadata['parameters'].values.map { |p| p['type'] }).to all(start_with('Optional['))
  end

  context 'with explicit null parameters' do
    let(:params) { { 'thresholds' => nil, 'format' => nil } }
    let(:icas) { [ica('c1.example.com', 'active', 80)] }

    it 'falls back to the defaults' do
      expect(STDOUT).to receive(:puts) { |output| expect(output).to include('c1.example.com') }

      run_expecting_exit(0)
    end
  end

  context "with format => 'json' reporting total and checked" do
    let(:params) { { 'format' => 'json' } }
    let(:icas) { [ica('c1.example.com', 'active', 80), ica('c2.example.com', 'revoked', 5), ica('c3.example.com', 'draining', 400)] }

    it 'reports total and checked counts so an empty result can be interpreted' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed).to include('total' => 3, 'checked' => 2)
        expect(parsed['icas'].map { |i| i['compiler-fqdn'] }).to eq(['c1.example.com'])
      end

      run_expecting_exit(0)
    end
  end

  context 'with a table report' do
    let(:icas) { [ica('c1.example.com', 'active', 80), ica('compiler-two.example.com', 'draining', 10)] }

    it 'prints an aligned header and one row per reported ICA in column order' do
      expect(STDOUT).to receive(:puts) do |output|
        lines = output.split("\n")
        expect(lines.first.split(%r{\s{2,}})).to eq(['COMPILER-FQDN', 'STATE', 'NOT-AFTER', 'DAYS-REMAINING', 'BAND'])
        expect(lines[1].split(%r{\s{2,}}).values_at(0, 1, 3, 4)).to eq(['c1.example.com', 'active', '80', '90'])
        expect(lines[2].split(%r{\s{2,}}).values_at(0, 1, 3, 4)).to eq(['compiler-two.example.com', 'draining', '10', '30'])
        expect(lines[1].index('active')).to eq(lines[2].index('draining'))
      end

      run_expecting_exit(1)
    end
  end

  context 'with a custom threshold and a json report' do
    let(:params) { { 'format' => 'json', 'thresholds' => [14, 7] } }
    let(:icas) { [ica('c1.example.com', 'active', 10)] }

    it 'places the ICA in the matching custom band' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['icas'].first['threshold-band']).to eq(14) }

      run_expecting_exit(0)
    end
  end

  context 'with custom thresholds and nothing in any band (table)' do
    let(:params) { { 'thresholds' => [14, 7] } }
    let(:icas) { [ica('c1.example.com', 'active', 20)] }

    it 'names the largest custom threshold in the message' do
      expect(STDOUT).to receive(:puts) { |output| expect(output).to include('within 14 days') }

      run_expecting_exit(0)
    end
  end

  context 'with a revoked ICA that has an unparseable not-after' do
    let(:icas) { [{ 'compiler-fqdn' => 'c1.example.com', 'state' => 'revoked', 'not-after' => 'garbage' }] }

    it 'ignores it, since excluded states are never parsed' do
      run_expecting_exit(0)
    end
  end

  context 'with an invalid format and invalid thresholds together' do
    let(:params) { { 'format' => 'xml', 'thresholds' => [] } }

    it 'reports the format first' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_format') }

      run_expecting_exit(2)
    end
  end

  context 'with an HTTP redirect' do
    let(:response) { instance_double(Net::HTTPResponse, code: '302', body: '') }

    it 'treats it as a failure' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_failed') }

      run_expecting_exit(2)
    end
  end

  context 'when the error body is not valid UTF-8' do
    let(:response) { instance_double(Net::HTTPResponse, code: '502', body: "bad \xE2\x82 gateway".b) }

    it 'still emits a structured error with exit 2' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_failed') }

      run_expecting_exit(2)
    end
  end

  [['a JSON string', '"abc"'], ['JSON null', 'null'], ['a JSON array', '[]']].each do |label, raw|
    context "when the response body is #{label}" do
      let(:response) { instance_double(Net::HTTPResponse, code: '200', body: raw) }

      it 'is an invalid-response error, not an unexpected one' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_response') }

        run_expecting_exit(2)
      end
    end
  end

  context 'when an ICA has no state' do
    let(:icas) { [{ 'compiler-fqdn' => 'c1.example.com', 'not-after' => '2027-01-01T00:00:00Z' }] }

    it 'is an invalid-response error rather than being silently skipped' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_invalid_response') }

      run_expecting_exit(2)
    end
  end

  context 'with a single threshold' do
    let(:params) { { 'thresholds' => [30] } }

    context 'and an ICA inside it' do
      let(:icas) { [ica('c1.example.com', 'active', 20)] }

      it 'exits 1, since the only band is the tightest' do
        run_expecting_exit(1)
      end
    end

    context 'and an ICA outside it' do
      let(:icas) { [ica('c1.example.com', 'active', 45)] }

      it 'exits 0' do
        run_expecting_exit(0)
      end
    end
  end

  [ScriptError, SystemStackError, NoMemoryError].each do |exception_class|
    context "when #{exception_class} is raised" do
      before(:each) { allow(https).to receive(:get).and_raise(exception_class) }

      it 'is still reported as a failed check with exit 2, never the alert code' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_unexpected') }

        run_expecting_exit(2)
      end
    end
  end

  context 'when stdout is a broken pipe while reporting a failure' do
    let(:response) { instance_double(Net::HTTPResponse, code: '500', body: 'x') }

    before(:each) { allow(STDOUT).to receive(:puts).and_raise(Errno::EPIPE) }

    it 'still exits 2' do
      run_expecting_exit(2)
    end
  end

  ['active', 'draining'].each do |state|
    [['null', nil], ['absent', :absent]].each do |label, value|
      context "with a #{state} ICA whose not-after is #{label}" do
        let(:icas) do
          entry = { 'compiler-fqdn' => 'c1.example.com', 'state' => state, 'not-after' => value }
          entry.delete('not-after') if value == :absent
          [entry, ica('c2.example.com', 'active', 400)]
        end

        it 'fails the whole check with exit 2 rather than skipping it' do
          expect(STDOUT).to receive(:puts) do |output|
            parsed = JSON.parse(output)['_error']
            expect(parsed['kind']).to eq('peadm/check_ica_expiry_invalid_response')
            expect(parsed['msg']).to include('c1.example.com')
          end

          run_expecting_exit(2)
        end
      end
    end
  end

  context 'when the error cannot be serialized (for example the json library failed to load)' do
    before(:each) do
      allow(https).to receive(:get).and_raise(RuntimeError, 'boom')
      allow(described_class).to receive(:error_json).and_raise(NoMethodError, "undefined method `to_json'")
    end

    it 'prints a hand-built fallback _error and still exits 2' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)['_error']
        expect(parsed['kind']).to eq('peadm/check_ica_expiry_unexpected')
        expect(parsed['msg']).to match(%r{could not be written})
      end

      run_expecting_exit(2)
    end
  end

  context 'when the exception raised cannot even produce its message (the error is still reported)' do
    let(:unreadable_error) do
      Class.new(StandardError) do
        def message
          raise 'message is broken'
        end
      end
    end

    before(:each) { allow(https).to receive(:get).and_raise(unreadable_error) }

    it 'still exits 2, never the alert code, and says the message was unreadable' do
      expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['msg']).to include('its message could not be read') }

      run_expecting_exit(2)
    end
  end

  it 'passes CA fields it does not interpret through to the json report' do
    json_task = described_class.new({ 'format' => 'json' }, https_client: https, now: now)
    body = { 'intermediate-cas' => [ica('c1.example.com', 'active', 80)] }
    allow(response).to receive(:body).and_return(body.to_json)
    expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['icas'].first).to include('provisioned-at' => '2026-01-01T00:00:00Z') }

    expect { json_task.execute! }.to raise_error(SystemExit)
  end

  describe '.run_from_stdin' do
    before(:each) do
      allow(Puppet).to receive(:initialize_settings)
      allow(STDIN).to receive(:read).and_return(stdin)
    end

    context 'with valid parameters on stdin' do
      let(:stdin) { { 'format' => 'json' }.to_json }

      before(:each) do
        allow(described_class).to(receive(:new).and_wrap_original { |original, given| original.call(given, https_client: https, now: now) })
      end

      it 'runs the check and exits 0 when nothing is in the tightest band' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)).to include('total' => 0, 'checked' => 0, 'icas' => []) }

        expect { described_class.run_from_stdin }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end

    context 'when a library cannot be loaded' do
      let(:stdin) { '{}' }

      before(:each) { allow(described_class).to receive(:require).and_raise(LoadError, 'cannot load such file -- puppet') }

      it 'exits 2 rather than the alert code' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_unexpected') }

        expect { described_class.run_from_stdin }.to raise_error(SystemExit) { |e| expect(e.status).to eq(2) }
      end
    end

    context 'with malformed JSON on stdin' do
      let(:stdin) { 'not json' }

      it 'exits 2 with a structured error rather than the alert code' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['kind']).to eq('peadm/check_ica_expiry_unexpected') }

        expect { described_class.run_from_stdin }.to raise_error(SystemExit) { |e| expect(e.status).to eq(2) }
      end
    end

    context 'with stdin that is not a JSON object' do
      let(:stdin) { '[]' }

      it 'exits 2' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['msg']).to include('JSON object') }

        expect { described_class.run_from_stdin }.to raise_error(SystemExit) { |e| expect(e.status).to eq(2) }
      end
    end

    context 'when Puppet settings cannot be initialized' do
      let(:stdin) { '{}' }

      before(:each) { allow(Puppet).to receive(:initialize_settings).and_raise(RuntimeError, 'no settings') }

      it 'exits 2' do
        expect(STDOUT).to receive(:puts) { |output| expect(JSON.parse(output)['_error']['msg']).to include('no settings') }

        expect { described_class.run_from_stdin }.to raise_error(SystemExit) { |e| expect(e.status).to eq(2) }
      end
    end
  end
end
