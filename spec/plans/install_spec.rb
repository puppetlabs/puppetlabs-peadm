require 'spec_helper'

describe 'peadm::install' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs successfully with the minimum required parameters' do
      expect_plan('peadm::subplans::install')
      expect_plan('peadm::subplans::configure')
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
      expect(run_plan('peadm::install', 'primary_host' => 'primary', 'console_password' => 'puppetLabs123!', 'version' => '2021.7.8')).to be_ok
    end
  end
end
