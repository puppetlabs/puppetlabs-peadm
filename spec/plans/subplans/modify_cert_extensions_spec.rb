require 'spec_helper'

describe 'peadm::subplans::modify_cert_extensions' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    context 'modifying a client certificate' do
      let(:params) do
        {
          'targets' => 'foo',
          'primary_host'     => 'primary',
          'primary_certname' => 'primary',
          'add'              => { 'pe_role' => 'puppet/server' },
        }
      end

      it 'runs successfully ' do
        expect_task('peadm::cert_data').be_called_times(1).return_for_targets(
          'primary' => { 'certificate-exists' => true,
                         'certname'           => 'primary',
                         'dns-alt-names'      => '',
                         'extensions'         => '' },
          'foo'     => { 'certificate-exists' => true,
                         'certname'           => 'foo',
                         'dns-alt-names'      => '',
                         'extensions'         => '' },
        )
        expect_command('systemctl is-active puppet.service')
        expect_command('systemctl stop puppet.service')
        expect_command('/opt/puppetlabs/bin/puppetserver ca clean --certname foo')
        allow_plan('peadm::util::insert_csr_extension_requests')
        allow_task('peadm::ssl_clean')
        allow_task('peadm::submit_csr')
        allow_task('peadm::sign_csr')
        expect_command('/opt/puppetlabs/bin/puppet ssl download_cert --certname foo || /opt/puppetlabs/bin/puppet certificate find --ca-location remote foo')
        allow_command('/opt/puppetlabs/bin/puppet facts upload')
        expect_command('systemctl start puppet.service')

        expect(run_plan('peadm::subplans::modify_cert_extensions', params)).to be_ok
      end
    end
  end
end
