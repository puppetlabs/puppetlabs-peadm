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
      allow_plan('peadm::modify_certificate').always_return({})
    end

    it 'signs the CSR directly when the primary cert is healthy' do
      stub_common!
      expect_task('peadm::submit_csr').be_called_times(1)
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(1)
      expect_task('peadm::sign_csr').be_called_times(1)

      expect(run_plan('peadm::subplans::prepare_agent', params)).to be_ok
    end

    it 'silently tolerates a non-revocation submit_csr error, matching pre-existing behavior' do
      stub_common!
      expect_task('peadm::submit_csr').be_called_times(1).return do |targets:, **_kwargs|
        Bolt::ResultSet.new([Bolt::Result.new(targets.first,
                                               value: {
                                                 '_error' => { 'msg' => 'already submitted', 'kind' => 'bolt/error' },
                                                 '_output' => 'already submitted',
                                               })])
      end
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(1)
      expect_task('peadm::sign_csr').be_called_times(1)

      expect(run_plan('peadm::subplans::prepare_agent', params)).to be_ok
    end
  end
end
