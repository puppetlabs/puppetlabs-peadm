require 'spec_helper'

describe 'peadm::uninstall' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs peadm::uninstall successfully with only primary_host as parameter' do
      expect_task('peadm::pe_uninstall')
      expect(run_plan('peadm::uninstall', 'primary_host' => 'primary')).to be_ok
    end
  end
end
