require 'spec_helper'

describe 'peadm::subplans::modify_certificate' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    context 'modifying a client certificate' do
      let(:params) do
        {
          'targets' => 'foo',
          'primary_host'     => 'primary',
          'primary_certname' => 'primary',
          'add_extensions'   => { 'pe_role' => 'puppet/server' },
        }
      end

      it 'runs successfully ' do
        expect_task('peadm::cert_data').be_called_times(1).return_for_targets(
          'primary' => { 'certificate-exists' => true,
                         'certname'           => 'primary',
                         'dns-alt-names'      => [],
                         'extensions'         => {} },
          'foo'     => { 'certificate-exists' => true,
                         'certname'           => 'foo',
                         'dns-alt-names'      => [],
                         'extensions'         => {} },
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

        expect(run_plan('peadm::subplans::modify_certificate', params)).to be_ok
      end

      it 'regenerates the primary cert, restarts the dependent services, and retries once when sign_csr hits "certificate revoked"' do
        allow_any_out_message
        allow_task('peadm::cert_data').return_for_targets(
          'primary' => { 'certificate-exists' => true,
                         'certname'           => 'primary',
                         'dns-alt-names'      => [],
                         'extensions'         => {} },
          'foo'     => { 'certificate-exists' => true,
                         'certname'           => 'foo',
                         'dns-alt-names'      => [],
                         'extensions'         => {} },
        )
        expect_command('systemctl is-active puppet.service')
        expect_command('systemctl stop puppet.service')
        expect_command('/opt/puppetlabs/bin/puppetserver ca clean --certname foo')
        allow_plan('peadm::util::insert_csr_extension_requests')
        allow_task('peadm::ssl_clean')
        allow_task('peadm::submit_csr')

        sign_attempts = 0
        expect_task('peadm::sign_csr').be_called_times(2).return do |targets:, **_kwargs|
          sign_attempts += 1
          result = if sign_attempts == 1
                     Bolt::Result.new(targets.first,
                                       value: {
                                         '_error' => { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                                         '_output' => 'Fatal error when running action \'sign\' Error: Failed ' \
                                                      'connecting to https://primary:8140/status/v1/services Root ' \
                                                      'cause: SSL_connect returned=1 errno=0 state=error: ' \
                                                      'certificate verify failed (certificate revoked)',
                                       })
                   else
                     Bolt::Result.new(targets.first, value: {})
                   end
          Bolt::ResultSet.new([result])
        end

        service_calls = []
        expect_task('service').be_called_times(5).return do |targets:, params:, **_kwargs|
          service_calls << [params['name'], params['action']]
          Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
        end
        allow_any_command
        expect_task('peadm::wait_until_service_ready')
        expect_command('/opt/puppetlabs/bin/puppet ssl download_cert --certname foo || /opt/puppetlabs/bin/puppet certificate find --ca-location remote foo')
        allow_command('/opt/puppetlabs/bin/puppet facts upload')
        expect_command('systemctl start puppet.service')

        expect(run_plan('peadm::subplans::modify_certificate', params)).to be_ok
        expect(sign_attempts).to eq(2)
        expected_service_calls = [
          ['pe-puppetserver', 'stop'],
          ['pe-puppetserver', 'start'],
          ['pe-console-services', 'restart'],
          ['pe-orchestration-services', 'restart'],
          ['pe-puppetdb', 'restart'],
        ]
        expect(service_calls).to eq(expected_service_calls)
      end
    end

    context 'modifying the primary certificate' do
      it 'fails if the primary is using the PCP transport' do
        result = run_plan('peadm::subplans::modify_certificate',
                          { 'targets'          => 'pcp://primary.example',
                            'primary_host'     => 'pcp://primary.example',
                            'primary_certname' => 'primary.example' })

        expect(result).not_to be_ok
        expect(result.value.kind).to eq('unexpected-transport')
        expect(result.value.msg).to match(%r{The "pcp" transport is not available for use with the Primary})
      end
    end
  end
end
