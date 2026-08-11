require 'spec_helper'

describe 'peadm::add_replica' do
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_apply
    allow_any_task
    allow_any_command
    allow_any_out_message
  end

  describe 'basic functionality' do
    let(:code_manager_enabled) { { 'code_manager_enabled' => true } }
    let(:params) { { 'primary_host' => 'primary', 'replica_host' => 'replica' } }
    let(:cfg) { { 'params' => { 'primary_host' => 'primary' } } }
    let(:certdata) do
      {
        'certificate-exists' => true,
        'certname'           => 'primary',
        'extensions'         => { '1.3.6.1.4.1.34380.1.1.9813' => 'A' },
        'dns-alt-names'      => []
      }
    end
    let(:certstatus) do
      {
        'certificate-status' => 'valid',
        'reason'             => 'Expires - 2099-01-01 00:00:00 UTC'
      }
    end

    it 'runs successfully when the primary does not have alt-names' do
      allow_standard_non_returning_calls
      expect_task('peadm::code_manager_enabled').always_return(code_manager_enabled)
      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(4)
      expect_task('peadm::cert_valid_status').always_return(certstatus)
      expect_task('package').always_return({ 'status' => 'uninstalled' })
      expect_task('peadm::agent_install')
        .with_params({ 'server'        => 'primary',
                       'install_flags' => [
                         'main:dns_alt_names=replica',
                         '--puppet-service-ensure', 'stopped',
                         'main:certname=replica'
                       ] })
      expect_plan('peadm::util::copy_file').be_called_times(5)

      expect_out_verbose.with_params('Current config is...')
      expect_out_verbose.with_params('Updating classification to...')
      expect(run_plan('peadm::add_replica', params)).to be_ok
    end

    it 'runs successfully when the primary has alt-names' do
      allow_standard_non_returning_calls
      expect_task('peadm::code_manager_enabled').always_return(code_manager_enabled)
      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::cert_data').always_return(certdata.merge({ 'dns-alt-names' => ['primary', 'alt'] })).be_called_times(4)
      expect_task('peadm::cert_valid_status').always_return(certstatus)
      expect_task('package').always_return({ 'status' => 'uninstalled' })
      expect_task('peadm::agent_install')
        .with_params({ 'server'        => 'primary',
                       'install_flags' => [
                         'main:dns_alt_names=replica,alt',
                         '--puppet-service-ensure', 'stopped',
                         'main:certname=replica'
                       ] })
      expect_plan('peadm::util::copy_file').be_called_times(5)

      expect_out_verbose.with_params('Current config is...')
      expect_out_verbose.with_params('Updating classification to...')
      expect(run_plan('peadm::add_replica', params)).to be_ok
    end

    it 'fails when code manager not enabled' do
      allow_standard_non_returning_calls
      expect_task('peadm::code_manager_enabled').always_return({ 'code_manager_enabled' => false })

      result = run_plan('peadm::add_replica', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{Code Manager must be enabled})
    end

    it 'fails and surfaces the error when provision_replica fails' do
      allow_standard_non_returning_calls
      expect_task('peadm::code_manager_enabled').always_return(code_manager_enabled)
      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(4)
      expect_task('peadm::cert_valid_status').always_return(certstatus)
      expect_task('package').always_return({ 'status' => 'uninstalled' })
      expect_plan('peadm::util::copy_file').be_called_times(5)
      expect_task('peadm::provision_replica')
        .error_with('msg' => 'The provided token has expired.',
                    'kind' => 'puppetlabs.rbac/token-expired')
        .be_called_times(1)

      expect_out_verbose.with_params('Current config is...')
      expect_out_verbose.with_params('Updating classification to...')
      result = run_plan('peadm::add_replica', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{peadm::provision_replica failed})
      # the real underlying task error must be surfaced, not masked
      expect(result.value.msg).to match(%r{The provided token has expired\.})
      # a token/authorization-shaped error should still get the RBAC hint
      expect(result.value.msg).to match(%r{RBAC token})
    end

    it 'does not append the RBAC token hint when the failure is unrelated to auth' do
      allow_standard_non_returning_calls
      expect_task('peadm::code_manager_enabled').always_return(code_manager_enabled)
      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(4)
      expect_task('peadm::cert_valid_status').always_return(certstatus)
      expect_task('package').always_return({ 'status' => 'uninstalled' })
      expect_plan('peadm::util::copy_file').be_called_times(5)
      # A non-transient, non-auth failure: no retry should be attempted, and
      # the RBAC hint would be misleading noise here.
      expect_task('peadm::provision_replica')
        .error_with('msg' => 'pg_basebackup: error: could not connect to server',
                    'kind' => 'puppetlabs.tasks/task-error')
        .be_called_times(1)

      expect_out_verbose.with_params('Current config is...')
      expect_out_verbose.with_params('Updating classification to...')
      result = run_plan('peadm::add_replica', params)
      expect(result).not_to be_ok
      expect(result.value.msg).to match(%r{pg_basebackup})
      expect(result.value.msg).not_to match(%r{RBAC token})
    end

    it 'retries provision_replica once and succeeds after a transient orchestrator connection-closed error' do
      allow_standard_non_returning_calls
      expect_task('peadm::code_manager_enabled').always_return(code_manager_enabled)
      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(4)
      expect_task('peadm::cert_valid_status').always_return(certstatus)
      expect_task('package').always_return({ 'status' => 'uninstalled' })
      expect_plan('peadm::util::copy_file').be_called_times(5)

      attempts = 0
      expect_task('peadm::provision_replica').return do |targets:, **_kwargs|
        attempts += 1
        results = targets.map do |target|
          if attempts == 1
            Bolt::Result.new(target,
                              error: { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                              message: '[Error]: An error has occurred while running orchestrated job. ' \
                                       'The orchestration service returned an error response. (status 500: ' \
                                       '{"msg":"org.apache.http.ConnectionClosedException: Connection closed ' \
                                       'unexpectedly","kind":"puppetlabs.orchestrator/unknown-error"})')
          else
            Bolt::Result.new(target, value: {})
          end
        end
        Bolt::ResultSet.new(results)
      end

      expect_out_verbose.with_params('Current config is...')
      expect_out_verbose.with_params('Updating classification to...')
      expect(run_plan('peadm::add_replica', params)).to be_ok
      expect(attempts).to eq(2)
    end

    it 'gives up after exhausting retries when the transient orchestrator error persists' do
      allow_standard_non_returning_calls
      expect_task('peadm::code_manager_enabled').always_return(code_manager_enabled)
      expect_task('peadm::get_peadm_config').always_return(cfg)
      expect_task('peadm::cert_data').always_return(certdata).be_called_times(4)
      expect_task('peadm::cert_valid_status').always_return(certstatus)
      expect_task('package').always_return({ 'status' => 'uninstalled' })
      expect_plan('peadm::util::copy_file').be_called_times(5)

      attempts = 0
      expect_task('peadm::provision_replica').return do |targets:, **_kwargs|
        attempts += 1
        results = targets.map do |target|
          Bolt::Result.new(target,
                            error: { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                            message: '[Error]: An error has occurred while running orchestrated job. ' \
                                     'The orchestration service returned an error response. (status 500: ' \
                                     '{"msg":"org.apache.http.ConnectionClosedException: Connection closed ' \
                                     'unexpectedly","kind":"puppetlabs.orchestrator/unknown-error"})')
        end
        Bolt::ResultSet.new(results)
      end

      expect_out_verbose.with_params('Current config is...')
      expect_out_verbose.with_params('Updating classification to...')
      result = run_plan('peadm::add_replica', params)
      expect(result).not_to be_ok
      expect(attempts).to eq(3)
      expect(result.value.msg).to match(%r{ConnectionClosedException})
      expect(result.value.msg).not_to match(%r{RBAC token})
    end
  end
end
