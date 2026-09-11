# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::poll_ica_approval' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_any_out_message
  end

  # peadm::get_request_status runs against $state['primary'], which starts as
  # 'primary' and may change to a resolved replica after failover. Interval
  # and timeout are kept at 1s/a couple of polls so the (real, unmocked)
  # ctrl::sleep between polls doesn't slow the suite down meaningfully.
  let(:base_params) do
    {
      'primary'      => 'primary',
      'request_id'   => 'req-1',
      'probe_target' => 'compiler',
      'timeout'      => 2,
      'interval'     => 1,
    }
  end

  def status_result(target, state, extra = {})
    Bolt::Result.new(target, value: { 'state' => state }.merge(extra), action: 'task', object: 'peadm::get_request_status')
  end

  def error_result(target, kind, msg)
    Bolt::Result.new(target, value: { '_error' => { 'kind' => kind, 'msg' => msg } }, action: 'task', object: 'peadm::get_request_status')
  end

  it 'returns approved => true immediately when the first poll is approved' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status')
      .with_params({ 'request_id' => 'req-1', '_catch_errors' => true })
      .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| status_result(t, 'approved') }) }

    result = run_plan('peadm::poll_ica_approval', base_params)
    expect(result).to be_ok
    expect(result.value['approved']).to eq(true)
    expect(result.value['primary'].map(&:name)).to eq(['primary'])
  end

  it 'fails the plan and surfaces the rejection-reason when rejected' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status')
      .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| status_result(t, 'rejected', 'rejection-reason' => 'compiler CSR failed policy check') }) }

    result = run_plan('peadm::poll_ica_approval', base_params)
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{rejected: compiler CSR failed policy check})
  end

  it 'keeps polling the same target while pending, and returns approved once it terminates' do
    allow_standard_non_returning_calls
    call_count = 0
    expect_task('peadm::get_request_status').be_called_times(2).return do |targets:, **_|
      call_count += 1
      state = (call_count == 1) ? 'pending' : 'approved'
      Bolt::ResultSet.new(targets.map { |t| status_result(t, state) })
    end

    result = run_plan('peadm::poll_ica_approval', base_params.merge('timeout' => 5))
    expect(result).to be_ok
    expect(result.value['approved']).to eq(true)
    expect(call_count).to eq(2)
  end

  it 'returns approved => false when every poll times out still pending' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status').be_called_times(2)
                                            .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| status_result(t, 'pending') }) }

    result = run_plan('peadm::poll_ica_approval', base_params)
    expect(result).to be_ok
    expect(result.value['approved']).to eq(false)
    expect(result.value['primary'].map(&:name)).to eq(['primary'])
  end

  it 'fails immediately on a 404, distinguishing it from a timeout' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status')
      .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| error_result(t, 'peadm/ica_request_not_found', 'No such ICA request: req-1') }) }

    result = run_plan('peadm::poll_ica_approval', base_params)
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{does not exist})
    expect(result.value.msg).to match(%r{not a timeout}i)
  end

  it 'fails naming the replica parameter when the primary is unreachable and no replica was given' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status')
      .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| error_result(t, 'puppetlabs.tasks/connect-error', 'connection refused') }) }

    result = run_plan('peadm::poll_ica_approval', base_params)
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{replica parameter})
  end

  it 'resolves the new primary and resumes polling there when the primary fails over' do
    allow_standard_non_returning_calls
    call_count = 0
    expect_task('peadm::get_request_status').be_called_times(2).return do |targets:, **_|
      call_count += 1
      target = targets.first
      if target.name == 'primary'
        Bolt::ResultSet.new([error_result(target, 'puppetlabs.tasks/connect-error', 'connection refused')])
      else
        Bolt::ResultSet.new([status_result(target, 'approved')])
      end
    end
    expect_task('peadm::resolve_current_primary')
      .with_params({ 'candidates' => ['replica'], '_catch_errors' => true })
      .always_return('primary_url' => 'https://replica:8140', 'resolved_from' => 'replica')

    result = run_plan('peadm::poll_ica_approval', base_params.merge('replica' => 'replica'))
    expect(result).to be_ok
    expect(result.value['approved']).to eq(true)
    expect(result.value['primary'].map(&:name)).to eq(['replica'])
  end

  it 'fails the plan when no failover candidate answers' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status')
      .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| error_result(t, 'puppetlabs.tasks/connect-error', 'connection refused') }) }
    expect_task('peadm::resolve_current_primary')
      .always_return('error' => 'no-reachable-candidate')

    result = run_plan('peadm::poll_ica_approval', base_params.merge('replica' => 'replica'))
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{no failover candidate answered})
  end

  it 'fails the plan naming the probe target when resolve_current_primary itself fails' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status')
      .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| error_result(t, 'puppetlabs.tasks/connect-error', 'connection refused') }) }
    expect_task('peadm::resolve_current_primary')
      .error_with('msg' => 'no ssh connection to compiler', 'kind' => 'puppetlabs.tasks/connect-error')

    result = run_plan('peadm::poll_ica_approval', base_params.merge('replica' => 'replica'))
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{resolve_current_primary itself failed on \[compiler\]})
    expect(result.value.msg).to match(%r{no ssh connection to compiler})
  end

  it 'fails the plan on an unrecognized task error kind rather than retrying silently' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_request_status')
      .return { |targets:, **_| Bolt::ResultSet.new(targets.map { |t| error_result(t, 'peadm/get_request_status_failed', 'primary returned HTTP 500') }) }

    result = run_plan('peadm::poll_ica_approval', base_params)
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{Failed to poll ICA request req-1 status})
    expect(result.value.msg).to match(%r{primary returned HTTP 500})
  end
end
