require 'spec_helper'

describe 'peadm::install' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs successfully with the minimum required parameters' do
      expect_plan('peadm::action::install')
      expect_plan('peadm::action::configure')
      expect(run_plan('peadm::install', 'primary_host' => 'primary', 'console_password' => 'puppetlabs')).to be_ok
    end
  end
end
