#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: restore a compiler's CA config from ICA mode back to CA-proxy
# mode. Runs on the compiler. Two independent edits, both idempotent:
#
#   1. bootstrap.cfg: drop the intermediate-ca-service entry (added at
#      promotion time) and ensure certificate-authority-disabled-service is
#      present, so the next puppetserver start loads neither
#      IntermediateCAService nor a local signing CA.
#   2. ca.conf: set certificate-authority.proxy-target so
#      reverse-proxy-ca-service knows where to forward CSRs once it takes
#      over -- which only happens after peadm::restart_ca_service actually
#      restarts the process; this task alone does not restart anything.
#
# Neither edit takes effect until that restart, which is why the calling
# plan's ordering (this task, then restart, then cleanup_ica_key_material,
# then decommission/revoke) is load-bearing rather than incidental.
class RestoreCaProxyBootstrap
  PROXY_TARGET_SETTING = 'certificate-authority.proxy-target'

  def initialize(params)
    @proxy_target = params.fetch('proxy_target', 'primary')
  end

  def execute!
    reverted = IcaTaskHelper.revert_bootstrap_to_proxy!
    unless reverted
      error!(
        "#{IcaTaskHelper.bootstrap_cfg_path} does not exist -- cannot confirm this compiler was reverted to " \
        'CA-proxy mode. A missing bootstrap.cfg on a promoted compiler indicates a broken or misconfigured ' \
        'puppetserver install, not an already-reverted one.',
        'peadm/restore_ca_proxy_bootstrap_missing_config',
      )
    end

    IcaTaskHelper.set_hocon_value!(IcaTaskHelper.ca_conf_path, PROXY_TARGET_SETTING, @proxy_target)
    STDOUT.puts({ 'proxy_target' => @proxy_target }.to_json)
    exit 0
  rescue StandardError => e
    error!(e.message, 'peadm/restore_ca_proxy_bootstrap_failed')
  end

  private

  def error!(msg, kind)
    STDOUT.puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  RestoreCaProxyBootstrap.new(JSON.parse(STDIN.read)).execute!
end
