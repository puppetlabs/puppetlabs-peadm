require 'spec_helper'

describe 'peadm::subplans::component_install' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_out_message
  end

  describe 'basic functionality' do
    let(:params) do
      {
        'targets'            => 'compiler',
        'primary_host'       => 'primary',
        'avail_group_letter' => 'A',
        'role'               => 'pe_compiler',
      }
    end

    let(:transient_message) do
      '[Error]: Could not update: Error 503 on SERVER: Attempted to borrow a ' \
        'JRubyInstance from the pool during a shutdown. Please try again.'
    end

    it 'runs successfully on a clean run' do
      allow_standard_non_returning_calls
      expect_plan('peadm::subplans::prepare_agent')
      expect_task('peadm::puppet_runonce').be_called_times(1)

      result = run_plan('peadm::subplans::component_install', params)
      expect(result).to be_ok
    end

    it 'retries once and succeeds after a transient 503 error' do
      allow_standard_non_returning_calls
      expect_plan('peadm::subplans::prepare_agent')

      attempts = 0
      expect_task('peadm::puppet_runonce').be_called_times(2).return do |targets:, **_kwargs|
        attempts += 1
        results = targets.map do |target|
          if attempts == 1
            Bolt::Result.new(target,
                              error: { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                              message: transient_message)
          else
            Bolt::Result.new(target, value: {})
          end
        end
        Bolt::ResultSet.new(results)
      end

      expect(run_plan('peadm::subplans::component_install', params)).to be_ok
      expect(attempts).to eq(2)
    end

    it 'gives up after exhausting retries when the transient error persists' do
      allow_standard_non_returning_calls
      expect_plan('peadm::subplans::prepare_agent')

      attempts = 0
      expect_task('peadm::puppet_runonce').be_called_times(3).return do |targets:, **_kwargs|
        attempts += 1
        results = targets.map do |target|
          Bolt::Result.new(target,
                            error: { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                            message: transient_message)
        end
        Bolt::ResultSet.new(results)
      end

      result = run_plan('peadm::subplans::component_install', params)
      expect(result).not_to be_ok
      expect(attempts).to eq(3)
      expect(result.value.msg).to match(%r{Error 503 on SERVER})
    end

    it 'does not retry a non-transient failure' do
      allow_standard_non_returning_calls
      expect_plan('peadm::subplans::prepare_agent')

      attempts = 0
      expect_task('peadm::puppet_runonce').be_called_times(1).return do |targets:, **_kwargs|
        attempts += 1
        results = targets.map do |target|
          Bolt::Result.new(target,
                            error: { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                            message: '[Error]: Could not retrieve catalog; skipping run')
        end
        Bolt::ResultSet.new(results)
      end

      result = run_plan('peadm::subplans::component_install', params)
      expect(result).not_to be_ok
      expect(attempts).to eq(1)
      expect(result.value.msg).to match(%r{Could not retrieve catalog})
    end
  end
end
