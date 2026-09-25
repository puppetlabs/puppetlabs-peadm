#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'timeout'

# Bolt task: restart pe-puppetserver on a compiler so a preceding
# bootstrap.cfg/ca.conf edit (peadm::restore_ca_proxy_bootstrap) takes
# effect. Idempotent -- restarting an already-proxy compiler is a normal
# systemd restart. Fails with the service's own `systemctl status` output if
# it does not come back active within the timeout, rather than assuming a
# non-erroring restart command means the service is actually up.
class RestartCaService
  SERVICE = 'pe-puppetserver'
  WAIT_TIMEOUT_SECONDS = 120
  POLL_INTERVAL_SECONDS = 2

  def execute!
    _out, _err, status = Open3.capture3('systemctl', 'restart', SERVICE)
    raise "Failed to restart #{SERVICE}:\n#{service_status}" unless status.success?

    wait_until_active!
    STDOUT.puts({ 'restarted' => true }.to_json)
    exit 0
  rescue StandardError => e
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/restart_ca_service_failed' } }.to_json)
    exit 1
  end

  private

  def wait_until_active!
    Timeout.timeout(WAIT_TIMEOUT_SECONDS) do
      loop do
        out, _err, status = Open3.capture3('systemctl', 'is-active', SERVICE)
        break if status.success? && out.strip == 'active'
        sleep POLL_INTERVAL_SECONDS
      end
    end
  rescue Timeout::Error
    raise "#{SERVICE} did not become active within #{WAIT_TIMEOUT_SECONDS}s of restarting:\n#{service_status}"
  end

  def service_status
    out, = Open3.capture3('systemctl', 'status', SERVICE, '--no-pager')
    out
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  RestartCaService.new.execute!
end
