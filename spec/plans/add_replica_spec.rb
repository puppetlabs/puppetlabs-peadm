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

      # provision/enable are now separate calls to the same task (action:
      # 'provision' then 'enable'); only the provision call is retried here.
      provision_attempts = 0
      expect_task('peadm::provision_replica').be_called_times(3).return do |targets:, params:, **_kwargs|
        action = params['action']
        results = targets.map do |target|
          if action == 'provision'
            provision_attempts += 1
            if provision_attempts == 1
              Bolt::Result.new(target,
                                error: { 'msg' => 'The task failed with exit code 1', 'kind' => 'bolt/error' },
                                message: '[Error]: An error has occurred while running orchestrated job. ' \
                                         'The orchestration service returned an error response. (status 500: ' \
                                         '{"msg":"org.apache.http.ConnectionClosedException: Connection closed ' \
                                         'unexpectedly","kind":"puppetlabs.orchestrator/unknown-error"})')
            else
              Bolt::Result.new(target, value: {})
            end
          else
            Bolt::Result.new(target, value: {})
          end
        end
        Bolt::ResultSet.new(results)
      end

      expect_out_verbose.with_params('Current config is...')
      expect_out_verbose.with_params('Updating classification to...')
      expect(run_plan('peadm::add_replica', params)).to be_ok
      expect(provision_attempts).to eq(2)
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
      expect_task('peadm::provision_replica').be_called_times(3).return do |targets:, **_kwargs|
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

  # PE-48202: replacing a replica that is still running. PE's
  # `puppet infrastructure forget` can't drop the primary's pglogical
  # replication slots while the old replica holds them open, so it fails
  # part-way and leaves the old replica pinned in PE HA Replica next to the
  # new one. The plan stops the old replica first when it can reach it.
  describe 'replacing a configured replica' do
    let(:params) { { 'primary_host' => 'primary', 'replica_host' => 'replica' } }
    let(:old_replica) { 'old-replica.example.com' }
    let(:cfg) { { 'params' => { 'primary_host' => 'primary', 'replica_host' => old_replica } } }
    let(:certdata) do
      {
        'certificate-exists' => true,
        'certname'           => 'primary',
        'extensions'         => { '1.3.6.1.4.1.34380.1.1.9813' => 'A' },
        'dns-alt-names'      => []
      }
    end
    # pxp-agent too: forgetting another node makes PE run Puppet on every
    # infrastructure node through the orchestrator, which would restart the
    # old replica's pe-postgresql and reopen the replication slots.
    let(:stop_command) { "systemctl stop puppet.service pxp-agent.service 'pe-*'" }

    # Records every command as [target names, command] in run order. Commands
    # in `failing` return a failed result with `failure_output` on stderr.
    def stub_plan(call_log, failing: [], failure_output: 'Error: boom', any_message: true)
      allow_apply
      allow_any_task
      # BoltSpec's catch-all out::message stub takes every call, so a test that
      # expects a specific message must not install it.
      allow_any_out_message if any_message
      allow_any_out_verbose
      allow_task('peadm::code_manager_enabled').always_return({ 'code_manager_enabled' => true })
      allow_task('peadm::get_peadm_config').always_return(cfg)
      allow_task('peadm::cert_data').always_return(certdata)
      allow_task('peadm::cert_valid_status').always_return({ 'certificate-status' => 'valid', 'reason' => 'ok' })
      allow_task('package').always_return({ 'status' => 'uninstalled' })
      allow_any_command.return do |targets:, command:, **|
        call_log << [targets.map(&:name), command]
        results = targets.map do |target|
          if failing.any? { |f| command.include?(f) }
            Bolt::Result.new(target, value: { 'stdout' => '', 'stderr' => failure_output, 'exit_code' => 1 },
                                     error: { 'msg' => 'The command failed with exit code 1',
                                              'kind' => 'puppetlabs.tasks/command-error', 'details' => { 'exit_code' => 1 } })
          else
            Bolt::Result.new(target, value: { 'stdout' => '' })
          end
        end
        Bolt::ResultSet.new(results)
      end
    end

    def index_of(call_log, command, target = nil)
      call_log.index { |names, cmd| cmd.include?(command) && (target.nil? || names.include?(target)) }
    end

    it 'stops the old replica before forgetting it' do
      call_log = []
      stub_plan(call_log)

      expect(run_plan('peadm::add_replica', params)).to be_ok

      stop = index_of(call_log, stop_command, old_replica)
      # A Puppet run already in progress (e.g. started by the orchestrator)
      # would start the services again after they were stopped, so the agent
      # is disabled and any run in progress waited for, first.
      script = call_log[stop][1]
      disable = script.index('/opt/puppetlabs/bin/puppet agent --disable')
      wait = script.index('agent_catalog_run_lockfile')
      expect(disable).not_to be_nil
      expect(wait).not_to be_nil
      expect(disable).to be < wait
      expect(wait).to be < script.index(stop_command)
      # Shell variables reach the shell literally (heredoc escaping), and only a
      # live Puppet process named in the lockfile is waited for or ended.
      expect(script).to include('--section agent', 'kill -0 "$pid"', %q(tr '\\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'puppet agent'), 'while running && [ "$n" -lt 120 ]')
      forget = index_of(call_log, "puppet infrastructure forget #{old_replica}", 'primary')
      forget_new = index_of(call_log, 'puppet infrastructure forget replica', 'primary')
      expect(stop).not_to be_nil
      expect(forget).not_to be_nil
      expect(stop).to be < forget
      # The old replica first, straight after stopping it: nothing in between
      # may restart its services.
      expect(forget).to be < forget_new
      expect(forget).to eq(stop + 1)
    end

    context 'when the inventory names the old replica by another name' do
      let(:inventory_data) do
        { 'targets' => [{ 'name' => '10.0.0.9', 'vars' => { 'certname' => old_replica } }] }
      end

      it 'stops it through the inventory target with that certname' do
        call_log = []
        stub_plan(call_log)

        expect(run_plan('peadm::add_replica', params)).to be_ok

        expect(index_of(call_log, stop_command, '10.0.0.9')).not_to be_nil
        expect(index_of(call_log, stop_command, old_replica)).to be_nil
      end
    end

    it 'carries on and forgets it when the old replica cannot be reached' do
      call_log = []
      expect_out_message.with_params("Couldn't stop the services on the previous replica #{old_replica}; continuing as if it were down.")
      stub_plan(call_log, failing: [stop_command], any_message: false)

      expect(run_plan('peadm::add_replica', params)).to be_ok

      expect(index_of(call_log, "puppet infrastructure forget #{old_replica}", 'primary')).not_to be_nil
    end

    it 'warns with the output when forgetting the old replica fails' do
      call_log = []
      expect_out_message.with_params(
        "WARN  Couldn't forget the previous replica #{old_replica} " \
        '(ERROR: replication slot "pgl_pe_rbac_x" is active for PID 42). Its old certificate may not have been revoked. ' \
        "Next: run 'puppet infrastructure forget #{old_replica}' on the primary, then check 'puppetserver ca list --all'.",
      )
      stub_plan(call_log, failing: ["puppet infrastructure forget #{old_replica}"],
                          failure_output: 'ERROR: replication slot "pgl_pe_rbac_x" is active for PID 42',
                          any_message: false)

      expect(run_plan('peadm::add_replica', params)).to be_ok
    end

    it 'keeps the end of a long forget output, without colour codes, in the warning' do
      call_log = []
      reason = 'ERROR: replication slot "pgl_pe_rbac_x" is active for PID 42'
      long_output = "\e[0;32mInfo: #{'x' * 600}\e[0m #{reason}"
      kept = ('x' * 600 + ' ' + reason)[-500, 500]
      expect_out_message.with_params(
        "WARN  Couldn't forget the previous replica #{old_replica} (...#{kept}). Its old certificate may not have been revoked. " \
        "Next: run 'puppet infrastructure forget #{old_replica}' on the primary, then check 'puppetserver ca list --all'.",
      )
      stub_plan(call_log, failing: ["puppet infrastructure forget #{old_replica}"], failure_output: long_output, any_message: false)

      expect(run_plan('peadm::add_replica', params)).to be_ok
    end

    context 'when the configured replica is the primary' do
      let(:cfg) { { 'params' => { 'primary_host' => 'primary', 'replica_host' => 'primary' } } }

      it "doesn't stop the primary's services" do
        call_log = []
        stub_plan(call_log)

        expect(run_plan('peadm::add_replica', params)).to be_ok

        expect(index_of(call_log, stop_command)).to be_nil
      end
    end

    context 'when no replica is configured yet' do
      let(:cfg) { { 'params' => { 'primary_host' => 'primary', 'replica_host' => nil } } }

      it 'stops nothing' do
        call_log = []
        stub_plan(call_log)

        expect(run_plan('peadm::add_replica', params)).to be_ok

        expect(index_of(call_log, stop_command)).to be_nil
      end
    end

    context 'when the configured replica is the new replica host' do
      let(:cfg) { { 'params' => { 'primary_host' => 'primary', 'replica_host' => 'replica' } } }

      it 'does not stop the new replica' do
        call_log = []
        stub_plan(call_log)

        expect(run_plan('peadm::add_replica', params)).to be_ok

        expect(index_of(call_log, stop_command)).to be_nil
      end
    end

    context 'when the new replica is named by IP in the inventory' do
      let(:params) { { 'primary_host' => 'primary', 'replica_host' => '10.0.0.7' } }
      let(:inventory_data) do
        { 'targets' => [{ 'name' => '10.0.0.7', 'vars' => { 'certname' => 'new-replica.example.com' } }] }
      end

      it 'forgets the new replica host by its certname' do
        call_log = []
        stub_plan(call_log)

        expect(run_plan('peadm::add_replica', params)).to be_ok

        expect(index_of(call_log, 'puppet infrastructure forget new-replica.example.com', 'primary')).not_to be_nil
        expect(index_of(call_log, 'puppet infrastructure forget 10.0.0.7')).to be_nil
      end
    end
  end
end
