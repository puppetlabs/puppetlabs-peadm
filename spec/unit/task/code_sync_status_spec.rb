require 'spec_helper'
require_relative '../../../tasks/code_sync_status'

describe CodeSyncStatus do
  subject(:task) { described_class.new(params) }

  let(:params) { { 'environments' => ['production'] } }

  describe '#execute!' do
    # Thin smoke test: catches a mutation that swallows sync_status's
    # return value instead of printing it.
    it 'prints sync_status.to_json' do
      allow(task).to receive(:sync_status).and_return('sync' => true, 'environments' => {})
      expect(STDOUT).to receive(:puts).with('{"sync":true,"environments":{}}')

      task.execute!
    end
  end

  describe '#api_status (HTTP plumbing)' do
    let(:https_dbl) { instance_double(Net::HTTP) }
    let(:request_dbl) { instance_double(Net::HTTP::Get) }

    before(:each) do
      allow(Puppet).to receive(:settings).and_return(certname: 'primary.example.com',
                                                      hostcert: '/etc/puppetlabs/puppet/ssl/certs/primary.pem',
                                                      hostprivkey: '/etc/puppetlabs/puppet/ssl/private_keys/primary.pem',
                                                      localcacert: '/etc/puppetlabs/puppet/ssl/certs/ca.pem')
      allow(File).to receive(:read).and_return('dummy-pem-contents')
      allow(OpenSSL::X509::Certificate).to receive(:new).and_return(instance_double(OpenSSL::X509::Certificate))
      allow(OpenSSL::PKey::RSA).to receive(:new).and_return(instance_double(OpenSSL::PKey::RSA))
      allow(Net::HTTP).to receive(:new).with('primary.example.com', 8140).and_return(https_dbl)
      allow(https_dbl).to receive(:use_ssl=)
      allow(https_dbl).to receive(:cert=)
      allow(https_dbl).to receive(:key=)
      allow(https_dbl).to receive(:verify_mode=)
      allow(https_dbl).to receive(:ca_file=)
      allow(Net::HTTP::Get).to receive(:new).with('/status/v1/services?level=debug').and_return(request_dbl)
    end

    # Catches a mutation to the hardcoded port (8140) or a dropped
    # `?level=debug` query param -- debug level is required for the
    # code-sync details this task depends on; without it, the endpoint
    # silently returns incomplete status.
    it 'requests /status/v1/services?level=debug on port 8140 and parses the JSON body' do
      response = instance_double(Net::HTTPOK, body: { 'file-sync-storage-service' => {} }.to_json)
      allow(https_dbl).to receive(:request).with(request_dbl).and_return(response)

      expect(task.send(:api_status)).to eq('file-sync-storage-service' => {})
    end
  end

  describe '#check_environment_list' do
    # Catches a mutation that drops .casecmp('all') == 0 in favor of exact
    # ==, which would fail to recognize 'ALL'/'All' as the sentinel.
    it 'returns the full visible environment list when a case-insensitive "all" sentinel is requested' do
      result = task.send(:check_environment_list, ['production', 'staging'], ['ALL'])
      expect(result).to eq(['production', 'staging'])
    end

    # Catches a mutation that returns the visible list's own contents
    # instead of the caller's requested names.
    it 'returns exactly the requested environment names, in the order given, for explicit requests' do
      result = task.send(:check_environment_list, ['production', 'staging', 'test'], ['staging', 'production'])
      expect(result).to eq(['staging', 'production'])
    end

    # Catches a mutation that drops the `|| raise(...)` guard, silently
    # continuing instead of erroring on an invalid environment.
    it 'raises when a requested environment is not in the visible list' do
      expect { task.send(:check_environment_list, ['production'], ['bogus']) }
        .to raise_error('Environment bogus is not visible and will not be checked')
    end

    # Catches a mutation that switches the visible-environment match to
    # case-sensitive, causing spurious "not visible" errors for a real,
    # differently-cased environment.
    it 'matches the visible environment list case-insensitively' do
      result = task.send(:check_environment_list, ['production'], ['Production'])
      expect(result).to eq(['Production'])
    end
  end

  describe '#check_environment_code' do
    let(:status_call) do
      {
        'file-sync-storage-service' => {
          'status' => {
            'repos' => {
              'puppet-code' => {
                'submodules' => {
                  'production' => { 'latest_commit' => { 'message' => "code-manager deploy signature: 'abc123'" } },
                },
              },
            },
            'clients' => {
              'compiler-a.example.com' => {
                'repos' => {
                  'puppet-code' => {
                    'submodules' => {
                      'production' => { 'latest_commit' => { 'message' => "code-manager deploy signature: 'abc123'" } },
                    },
                  },
                },
              },
              'compiler-b.example.com' => {
                'repos' => {
                  'puppet-code' => {
                    'submodules' => {
                      'production' => { 'latest_commit' => { 'message' => "code-manager deploy signature: 'stale999'" } },
                    },
                  },
                },
              },
            },
          },
        },
      }
    end

    # Catches a mutation that reuses the primary's .dig path (rooted at
    # 'repos') for servers too, which would compare a value against
    # itself and always report sync: true regardless of real drift.
    it "reads each server's commit via the clients-rooted dig path, distinct from the primary path" do
      result = task.send(:check_environment_code, 'production', ['compiler-a.example.com', 'compiler-b.example.com'], status_call)
      expect(result['latest_commit']).to eq('abc123')
      expect(result['servers']['compiler-a.example.com']['commit']).to eq('abc123')
      expect(result['servers']['compiler-b.example.com']['commit']).to eq('stale999')
    end

    # Catches a mutation that inverts the == comparison.
    it 'marks a server in sync only when its commit exactly matches the primary commit' do
      result = task.send(:check_environment_code, 'production', ['compiler-a.example.com', 'compiler-b.example.com'], status_call)
      expect(result['servers']['compiler-a.example.com']['sync']).to eq(true)
      expect(result['servers']['compiler-b.example.com']['sync']).to eq(false)
    end

    # Catches a mutation that uses .any? instead of .all?, which would
    # mask real drift as long as one server happened to match.
    it 'reports sync: false overall when any one server is out of sync' do
      result = task.send(:check_environment_code, 'production', ['compiler-a.example.com', 'compiler-b.example.com'], status_call)
      expect(result['sync']).to eq(false)
    end
  end

  describe '#sync_status' do
    # Catches a mutation that uses .any? instead of .all? at the
    # environment level, and a mutation that iterates over all visible
    # environments instead of only the ones actually requested via
    # @params['environments'].
    it 'is sync: true only when every requested (not every visible) environment reports sync: true' do
      status_call = {
        'file-sync-storage-service' => {
          'status' => {
            'clients' => { 'compiler-a.example.com' => {} },
            'repos' => { 'puppet-code' => { 'submodules' => { 'production' => {}, 'staging' => {} } } },
          },
        },
      }
      allow(task).to receive(:api_status).and_return(status_call)
      allow(task).to receive(:check_environment_code)
        .with('production', ['compiler-a.example.com'], status_call)
        .and_return('sync' => true)

      result = task.send(:sync_status)
      expect(result['sync']).to eq(true)
      # 'staging' is visible but was never requested (params only asked for
      # 'production'), so it must not appear in the checked results.
      expect(result['environments'].keys).to eq(['production'])
    end
  end
end
