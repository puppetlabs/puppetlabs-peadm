require 'spec_helper'

describe 'peadm::subplans::configure' do
  include BoltSpec::Plans

  describe 'Standard architecture without DR' do
    it 'runs successfully' do
      allow_apply
      allow_any_task
      allow_any_plan
      allow_any_command

      expect_task('peadm::util::copy_file').not_be_called
      expect_task('peadm::provision_replica').not_be_called
      expect_task('peadm::code_manager').not_be_called

      expect(run_plan('peadm::subplans::configure', 'primary_host' => 'primary')).to be_ok
    end
  end

  describe 'Standard architecture with DR' do
    it 'waits for the primary only before provisioning the replica' do
      allow_apply
      allow_any_task
      allow_any_plan
      allow_any_command

      expect_task('peadm::wait_until_service_ready').be_called_times(1)
      expect_task('peadm::provision_replica').be_called_times(1)

      expect(run_plan('peadm::subplans::configure',
                       'primary_host' => 'primary',
                       'replica_host' => 'replica')).to be_ok
    end
  end

  describe 'Extra Large architecture with DR' do
    it 'waits for the primary and the postgresql host before provisioning the replica' do
      allow_apply
      allow_any_task
      allow_any_plan
      allow_any_command

      expect_task('peadm::wait_until_service_ready').be_called_times(2)
      expect_task('peadm::provision_replica').be_called_times(1)

      expect(run_plan('peadm::subplans::configure',
                       'primary_host'             => 'primary',
                       'replica_host'             => 'replica',
                       'primary_postgresql_host'  => 'primary_postgresql',
                       'replica_postgresql_host'  => 'replica_postgresql')).to be_ok
    end
  end

  describe 'Extra Large architecture with DR, provision_replica flaky' do
    it 'retries provision_replica and still succeeds' do
      allow_apply
      allow_any_task
      allow_any_plan
      allow_any_command
      allow_any_out_message

      attempts = 0
      expect_task('peadm::provision_replica').return { |targets:, **|
        attempts += 1
        results = targets.map do |target|
          if attempts == 1
            Bolt::Result.new(target, error: { 'msg' => 'PuppetDB not ready', 'kind' => 'puppetlabs.tasks/race' })
          else
            Bolt::Result.new(target, value: {})
          end
        end
        Bolt::ResultSet.new(results)
      }.be_called_times(2)

      expect(run_plan('peadm::subplans::configure',
                       'primary_host'             => 'primary',
                       'replica_host'             => 'replica',
                       'primary_postgresql_host'  => 'primary_postgresql',
                       'replica_postgresql_host'  => 'replica_postgresql')).to be_ok
    end
  end
end
