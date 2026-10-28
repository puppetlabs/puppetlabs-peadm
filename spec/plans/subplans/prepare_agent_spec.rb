require 'spec_helper'

describe 'peadm::subplans::prepare_agent' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    let(:params) do
      {
        'targets'                => 'agent',
        'primary_host'           => 'primary',
        'certificate_extensions' => { 'pe_role' => 'puppet/server' },
      }
    end
    let(:certstatus) do
      { 'certificate-status' => 'valid', 'reason' => 'Expires - 2099-01-01 00:00:00 UTC' }
    end
    let(:certdata) do
      { 'certificate-exists' => true, 'certname' => 'agent', 'extensions' => {}, 'dns-alt-names' => [] }
    end
    let(:primary_certdata) do
      { 'certificate-exists' => true, 'certname' => 'primary', 'extensions' => {}, 'dns-alt-names' => [] }
    end

    def stub_common!
      allow_any_out_message
      expect_task('package').always_return({ 'status' => 'installed' })
      expect_command('systemctl stop puppet.service')
      allow_command('/opt/puppetlabs/bin/puppet config set --section main server primary')
      allow_command('/opt/puppetlabs/bin/puppet config delete --section agent server_list')
      expect_task('peadm::cert_valid_status').always_return(certstatus)
      expect_task('peadm::submit_csr')
      allow_plan('peadm::modify_certificate').always_return({})
    end

    it 'signs the CSR directly when the primary cert is healthy' do
      stub_common!
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(1)
      expect_task('peadm::sign_csr').be_called_times(1)

      expect(run_plan('peadm::subplans::prepare_agent', params)).to be_ok
    end

    it 'regenerates the primary cert and retries once when sign_csr hits "certificate revoked"' do
      stub_common!
      expect_task('peadm::cert_data').return do |targets:, **_kwargs|
        value = (targets.first.name == 'primary') ? primary_certdata : certdata
        Bolt::ResultSet.new([Bolt::Result.new(targets.first, value: value)])
      end

      sign_attempts = 0
      expect_task('peadm::sign_csr').be_called_times(2).return do |targets:, **_kwargs|
        sign_attempts += 1
        if sign_attempts == 1
          Bolt::Result.new(targets.first,
                            value: {
                              '_error' => { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                              '_output' => 'Fatal error when running action \'sign\' Error: Failed connecting to ' \
                                           'https://primary:8140/status/v1/services Root cause: SSL_connect ' \
                                           'returned=1 errno=0 state=error: certificate verify failed (certificate revoked)',
                            })
        else
          Bolt::Result.new(targets.first, value: {})
        end
      end

      expect_task('service').be_called_times(2)
      # The exact rm -f / puppetserver ca generate heredoc text isn't this
      # test's concern -- only the detect/regen/retry control flow is.
      allow_any_command
      expect_task('peadm::wait_until_service_ready')

      expect(run_plan('peadm::subplans::prepare_agent', params)).to be_ok
      expect(sign_attempts).to eq(2)
    end

    it 'fails fast on a non-revocation sign_csr error without attempting a regen' do
      stub_common!
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(1)
      expect_task('peadm::sign_csr').be_called_times(1).return do |targets:, **_kwargs|
        Bolt::Result.new(targets.first,
                          value: {
                            '_error' => { 'msg' => 'The provided token has expired.',
                                          'kind' => 'puppetlabs.rbac/token-expired' },
                            '_output' => 'The provided token has expired.',
                          })
      end

      result = run_plan('peadm::subplans::prepare_agent', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{peadm::sign_csr failed})
      expect(result.value.msg).to match(%r{token has expired})
    end
  end
end
