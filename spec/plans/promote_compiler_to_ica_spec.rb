# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::promote_compiler_to_ica' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_any_out_message
  end

  let(:params) { { 'compiler' => 'compiler', 'primary' => 'primary' } }

  it 'runs the full workflow for a fresh promotion' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_ica_state')
      .with_params({ 'compiler_fqdn' => 'compiler' })
      .always_return('state' => 'none')
    expect_task('peadm::submit_ica_csr').always_return('request-id' => 'req-1')
    expect_plan('peadm::poll_ica_approval')
      .always_return('approved' => true, 'primary' => ['primary'])
    expect_task('peadm::install_ica_cert')
      .with_params({ 'primary_host' => 'primary' })
      .always_return('status' => 'installed')
    expect_task('peadm::validate_ica_compiler')
      .with_params({ 'primary_host' => 'primary' })
      .always_return('valid' => true)

    result = run_plan('peadm::promote_compiler_to_ica', params)
    expect(result).to be_ok
    expect(result.value).to match(%r{promoted to an ICA compiler})
  end

  it 'skips submission and polling when the primary already reports an active ICA' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_ica_state').always_return('state' => 'active')
    expect_task('peadm::submit_ica_csr').not_be_called
    expect_plan('peadm::poll_ica_approval').not_be_called
    expect_task('peadm::install_ica_cert').always_return('status' => 'already-installed')
    expect_task('peadm::validate_ica_compiler').always_return('valid' => true)

    result = run_plan('peadm::promote_compiler_to_ica', params)
    expect(result).to be_ok
  end

  it 'skips CSR submission and polls the supplied id when resume_request_id is given' do
    allow_standard_non_returning_calls
    polled_request_id = nil
    expect_task('peadm::get_ica_state').always_return('state' => 'none')
    expect_task('peadm::submit_ica_csr').not_be_called
    expect_plan('peadm::poll_ica_approval').return do |params:, **_|
      polled_request_id = params['request_id']
      Bolt::PlanResult.new({ 'approved' => true, 'primary' => ['primary'] }, 'success')
    end
    expect_task('peadm::install_ica_cert').always_return('status' => 'installed')
    expect_task('peadm::validate_ica_compiler').always_return('valid' => true)

    result = run_plan('peadm::promote_compiler_to_ica', params.merge('resume_request_id' => 'req-existing'))
    expect(result).to be_ok
    expect(polled_request_id).to eq('req-existing')
  end

  it 'ignores resume_request_id when the primary already reports an active ICA' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_ica_state').always_return('state' => 'active')
    expect_task('peadm::submit_ica_csr').not_be_called
    expect_plan('peadm::poll_ica_approval').not_be_called
    expect_task('peadm::install_ica_cert').always_return('status' => 'already-installed')
    expect_task('peadm::validate_ica_compiler').always_return('valid' => true)
    # Pins precedence, not just "nothing crashes": if $already_provisioned
    # stopped short-circuiting ahead of $resume_request_id, this message
    # (only emitted on the resume_request_id branch) would fire.
    expect_out_message.with_params('Resuming approval poll for request req-stale. No new CSR submitted.').not_be_called

    result = run_plan('peadm::promote_compiler_to_ica', params.merge('resume_request_id' => 'req-stale'))
    expect(result).to be_ok
  end

  it 'fails with the resume instructions when approval times out' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_ica_state').always_return('state' => 'none')
    expect_task('peadm::submit_ica_csr').always_return('request-id' => 'req-1')
    expect_plan('peadm::poll_ica_approval').always_return('approved' => false, 'primary' => ['primary'])
    expect_task('peadm::install_ica_cert').not_be_called
    expect_task('peadm::validate_ica_compiler').not_be_called

    result = run_plan('peadm::promote_compiler_to_ica', params)
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{still pending after 3600s})
    expect(result.value.msg).to match(%r{resume_request_id => 'req-1'})
  end

  it 'uses the resolved primary from a failover for install and validate' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_ica_state').always_return('state' => 'none')
    expect_task('peadm::submit_ica_csr').always_return('request-id' => 'req-1')
    expect_plan('peadm::poll_ica_approval').always_return('approved' => true, 'primary' => ['replica'])
    expect_task('peadm::install_ica_cert')
      .with_params({ 'primary_host' => 'replica' })
      .always_return('status' => 'installed')
    expect_task('peadm::validate_ica_compiler')
      .with_params({ 'primary_host' => 'replica' })
      .always_return('valid' => true)

    result = run_plan('peadm::promote_compiler_to_ica', params)
    expect(result).to be_ok
  end

  it 'fails with the revert message when validation fails' do
    allow_standard_non_returning_calls
    expect_task('peadm::get_ica_state').always_return('state' => 'none')
    expect_task('peadm::submit_ica_csr').always_return('request-id' => 'req-1')
    expect_plan('peadm::poll_ica_approval').always_return('approved' => true, 'primary' => ['primary'])
    expect_task('peadm::install_ica_cert').always_return('status' => 'installed')
    expect_task('peadm::validate_ica_compiler').always_return('valid' => false, 'error' => 'chain did not verify')

    result = run_plan('peadm::promote_compiler_to_ica', params)
    expect(result).not_to be_ok
    expect(result.value.msg).to match(%r{chain did not verify})
    expect(result.value.msg).to match(%r{reverted to proxy mode})
  end
end
