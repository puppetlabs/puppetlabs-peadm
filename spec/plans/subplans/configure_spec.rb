require 'spec_helper'

describe 'peadm::subplans::configure' do
  include BoltSpec::Plans

  describe 'Standard architecture without DR' do
    it 'runs successfully' do
      allow_apply
      allow_any_task
      allow_any_plan
      allow_any_command

      expect_task('peadm::read_file').always_return({ 'content' => 'mock' })
      expect_task('peadm::provision_replica').not_be_called
      expect_task('peadm::code_manager').not_be_called

      expect(run_plan('peadm::subplans::configure', 'primary_host' => 'primary')).to be_ok
    end
  end
end
