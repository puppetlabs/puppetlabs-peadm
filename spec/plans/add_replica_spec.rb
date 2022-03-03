require 'spec_helper'

describe 'peadm::add_replica' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_apply
    allow_any_task
    allow_any_command
  end

  describe 'basic functionality' do
    let(:params) { { 'primary_host' => 'primary', 'replica_host' => 'replica' } }
    let(:certdata) { { 'certname' => 'primary', 'extensions' => { '1.3.6.1.4.1.34380.1.1.9813' => 'A' } } }

    it 'runs successfully when the primary doesn\'t have alt-names' do
      allow_standard_non_returning_calls
      expect_task('peadm::cert_data').always_return(certdata)
      expect_task('peadm::agent_install')
        .with_params({ 'server'        => 'primary',
                       'install_flags' => [
                         '--puppet-service-ensure', 'stopped',
                         'main:certname=replica',
                         'main:dns_alt_names=replica'
                       ] })

      expect(run_plan('peadm::add_replica', params)).to be_ok
    end

    it 'runs successfully when the primary has alt-names' do
      allow_standard_non_returning_calls
      expect_task('peadm::cert_data').always_return(certdata.merge({ 'dns-alt-names' => ['primary', 'alt'] }))
      expect_task('peadm::agent_install')
        .with_params({ 'server'        => 'primary',
                       'install_flags' => [
                         '--puppet-service-ensure', 'stopped',
                         'main:certname=replica',
                         'main:dns_alt_names=replica,alt'
                       ] })

      expect(run_plan('peadm::add_replica', params)).to be_ok
    end
  end
end
