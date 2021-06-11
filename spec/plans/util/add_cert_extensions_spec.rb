# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::util::add_cert_extensions' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:each) do
    BoltSpec::Plans.init
  end

  describe 'basic functionality' do
    it 'runs successfully against multiple targets' do
      expect_task('peadm::trusted_facts').be_called_times(2).return_for_targets(
        'primary' => { 'certname'      => 'primary',
                       'dns-alt-names' => '',
                       'extensions'    => '' },
        'foo'     => { 'certname'      => 'foo',
                       'dns-alt-names' => '',
                       'extensions'    => '' },
        'bar'     => { 'certname'      => 'bar',
                       'dns-alt-names' => '',
                       'extensions'    => '' },
      )
      expect_command('systemctl is-active puppet.service').be_called_times(2)
      expect_command('systemctl stop puppet.service').be_called_times(2)
      expect_command('/opt/puppetlabs/bin/puppetserver ca clean --certname foo')
      expect_command('/opt/puppetlabs/bin/puppetserver ca clean --certname bar')
      allow_plan('peadm::util::insert_csr_extension_requests')
      allow_task('peadm::ssl_clean')
      allow_task('peadm::submit_csr')
      allow_task('peadm::sign_csr')
      expect_command('/opt/puppetlabs/bin/puppet ssl download_cert --certname foo || /opt/puppetlabs/bin/puppet certificate find --ca-location remote foo')
      expect_command('/opt/puppetlabs/bin/puppet ssl download_cert --certname bar || /opt/puppetlabs/bin/puppet certificate find --ca-location remote bar')
      allow_command('/opt/puppetlabs/bin/puppet facts upload')
      expect_command('systemctl start puppet.service').be_called_times(2)
      expect(run_plan('peadm::util::add_cert_extensions', 'primary_host' => 'primary', 'targets' => 'foo,bar', 'extensions' => { 'pe_role' => 'puppet/server' })).to be_ok
    end
  end
end
