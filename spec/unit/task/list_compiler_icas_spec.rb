require 'spec_helper'
require_relative '../../../tasks/list_compiler_icas'

describe ListCompilerIcas do
  subject(:task) { described_class.new(params, https_client: https) }

  let(:params) { {} }
  let(:https) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPResponse, code: '200', body: intermediate_cas.to_json) }
  let(:intermediate_cas) do
    {
      'intermediate-cas' => [
        {
          'compiler-fqdn' => 'compiler1.example.com',
          'state' => 'active',
          'provisioned-at' => '2026-01-01T00:00:00Z',
          'not-after' => '2027-01-01T00:00:00Z',
        },
        {
          'compiler-fqdn' => 'compiler2.example.com',
          'state' => 'decommissioned',
          'provisioned-at' => '2025-01-01T00:00:00Z',
          'not-after' => '2026-01-01T00:00:00Z',
        },
      ],
      'autosign-inconsistent' => false,
      'autosign-fingerprint-baseline' => 'abc123',
    }
  end

  before(:each) do
    allow(STDOUT).to receive(:puts)
    allow(https).to receive(:get).with('/puppet-ca/v1/intermediate-ca').and_return(response)
  end

  it 'returns one row per ICA with FQDN, state, provisioned-at, and not-after' do
    expect(STDOUT).to receive(:puts) do |output|
      expect(output).to include('compiler1.example.com', 'active', '2026-01-01T00:00:00Z', '2027-01-01T00:00:00Z')
    end

    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
  end

  it 'labels columns with a header and aligns them by width' do
    expect(STDOUT).to receive(:puts) do |output|
      lines = output.split("\n")
      expect(lines.first).to match(%r{COMPILER-FQDN}i).and match(%r{STATE}i).and match(%r{PROVISIONED-AT}i).and match(%r{NOT-AFTER}i)

      header_columns = lines[0].split(%r{\s{2,}})
      row_columns = lines[1].split(%r{\s{2,}})
      expect(row_columns.length).to eq(header_columns.length)
    end

    expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
  end

  context 'with a state filter' do
    let(:params) { { 'state' => 'active' } }

    it 'returns only ICAs matching the requested state' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to include('compiler1.example.com')
        expect(output).not_to include('compiler2.example.com')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'with an unknown state value' do
    let(:params) { { 'state' => 'bogus' } }

    it 'fails and lists the valid states' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['msg']).to include('bogus', 'active', 'draining', 'revoked', 'decommissioned')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context "with format => 'json'" do
    let(:params) { { 'format' => 'json' } }

    it "returns the endpoint's structure unmodified" do
      expect(STDOUT).to receive(:puts) do |output|
        expect(JSON.parse(output)).to eq(intermediate_cas)
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    context 'combined with a state filter' do
      let(:params) { { 'format' => 'json', 'state' => 'active' } }

      it 'keeps the same envelope shape but drops non-matching entries, passing fields through verbatim' do
        expect(STDOUT).to receive(:puts) do |output|
          parsed = JSON.parse(output)
          expect(parsed['intermediate-cas'].map { |ica| ica['compiler-fqdn'] }).to eq(['compiler1.example.com'])
          expect(parsed['intermediate-cas'].first).to eq(intermediate_cas['intermediate-cas'].first)
        end

        expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end
  end

  context 'with a state filter that matches nothing, but the fleet is not empty' do
    let(:params) { { 'state' => 'draining' } }

    it 'distinguishes "no match for this state" from "fleet is empty"' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to include('draining')
        expect(output).not_to eq('no compiler ICAs are provisioned')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end

  context 'with no ICAs registered' do
    let(:intermediate_cas) { { 'intermediate-cas' => [], 'autosign-inconsistent' => false, 'autosign-fingerprint-baseline' => nil } }

    it 'exits zero with an explicit human-readable message in table format' do
      expect(STDOUT).to receive(:puts).with('no compiler ICAs are provisioned')

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    context "with format => 'json'" do
      let(:params) { { 'format' => 'json' } }

      it 'returns the unmodified empty envelope, not a message' do
        expect(STDOUT).to receive(:puts) do |output|
          expect(JSON.parse(output)).to eq(intermediate_cas)
        end

        expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end
  end

  context 'when the connection to the primary fails' do
    before(:each) do
      allow(https).to receive(:get).and_raise(Errno::ECONNREFUSED)
    end

    it 'exits non-zero through the _error envelope instead of crashing' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/list_compiler_icas_connection_failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the TLS handshake fails (e.g. an expired or rotated hostcert)' do
    before(:each) do
      allow(https).to receive(:get).and_raise(OpenSSL::SSL::SSLError)
    end

    it 'exits non-zero through the _error envelope instead of crashing' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['kind']).to eq('peadm/list_compiler_icas_tls_failed')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'when the primary responds with a non-2xx status' do
    let(:response) { instance_double(Net::HTTPResponse, code: '503', body: 'CA service unavailable') }

    it 'exits non-zero surfacing the primary error body' do
      expect(STDOUT).to receive(:puts) do |output|
        parsed = JSON.parse(output)
        expect(parsed['_error']['msg']).to include('503', 'CA service unavailable')
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end

  context 'with autosign fingerprint divergence across the fleet' do
    let(:intermediate_cas) do
      {
        'intermediate-cas' => [
          {
            'compiler-fqdn' => 'compiler1.example.com',
            'state' => 'active',
            'provisioned-at' => '2026-01-01T00:00:00Z',
            'not-after' => '2027-01-01T00:00:00Z',
            'autosign-config-fingerprint' => 'aaa',
            'autosign-state' => 'divergent',
          },
          {
            'compiler-fqdn' => 'compiler2.example.com',
            'state' => 'active',
            'provisioned-at' => '2026-01-01T00:00:00Z',
            'not-after' => '2027-01-01T00:00:00Z',
            'autosign-config-fingerprint' => 'bbb',
            'autosign-state' => 'divergent',
          },
        ],
        'autosign-inconsistent' => true,
        'autosign-fingerprint-baseline' => nil,
      }
    end

    it 'shows each row autosign fingerprint and prints a warning naming the affected compilers' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to include('aaa', 'bbb', 'compiler1.example.com', 'compiler2.example.com')
        expect(output).to match(%r{warning}i)
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end

    context 'when a state filter excludes the diverging compilers' do
      let(:params) { { 'state' => 'decommissioned' } }

      it 'still names the diverging compilers, not nobody' do
        expect(STDOUT).to receive(:puts) do |output|
          expect(output).to match(%r{warning}i)
          expect(output).to include('compiler1.example.com', 'compiler2.example.com')
        end

        expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end
    end
  end

  context 'with a revoked ICA (no autosign state)' do
    let(:intermediate_cas) do
      {
        'intermediate-cas' => [
          {
            'compiler-fqdn' => 'compiler1.example.com',
            'state' => 'revoked',
            'provisioned-at' => '2026-01-01T00:00:00Z',
            'not-after' => '2027-01-01T00:00:00Z',
            'autosign-config-fingerprint' => 'aaa',
            'autosign-state' => nil,
          },
        ],
        'autosign-inconsistent' => false,
        'autosign-fingerprint-baseline' => 'aaa',
      }
    end

    it 'shows a dash for autosign state rather than a blank' do
      expect(STDOUT).to receive(:puts) do |output|
        expect(output).to match(%r{compiler1\.example\.com\s+revoked\s+.*\s-(\s|$)})
      end

      expect { task.execute! }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
    end
  end
end
