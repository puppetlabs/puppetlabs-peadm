#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: gracefully decommission a compiler's (already-draining)
# Intermediate CA. Runs on the primary. POSTs
# /puppet-ca/v1/intermediate-ca/:fqdn/decommission -- the default,
# non-revoking path of a demote. Unlike revoke, this performs no CRL step at
# all: agent certificates the ICA signed remain valid until they naturally
# renew, since decommission is meant to be a graceful, non-disruptive
# removal rather than the emergency-invalidation path revoke is. Requires
# the same RBAC token as revoke_compiler_ica, since this route carries no
# certname allowance either.
#
# This is a standalone task rather than a higher-level plan that drives its
# own drain-then-decommission lifecycle, so a caller that has already
# drained and waited out its own quiet period isn't forced to repeat that
# work just to reach the primary-side decommission call.
class DecommissionCompilerIca
  def initialize(params)
    @compiler_fqdn = params.fetch('compiler_fqdn')
    @token_file = params['token_file']
  end

  def execute!
    IcaTaskHelper.validate_fqdn!(@compiler_fqdn)
    response = https.request(decommission_request)

    unless response.code == '200'
      error!("Failed to decommission Intermediate CA for #{@compiler_fqdn}: HTTP #{response.code} - #{response.body}", 'peadm/decommission_compiler_ica_failed')
    end

    STDOUT.puts(response.body)
    exit 0
  rescue StandardError => e
    error!(e.message, 'peadm/decommission_compiler_ica_failed')
  end

  private

  def decommission_request
    req = Net::HTTP::Post.new("/puppet-ca/v1/intermediate-ca/#{@compiler_fqdn}/decommission")
    req['X-Authentication'] = IcaTaskHelper.rbac_token(@token_file)
    req
  end

  def https
    IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)
  end

  def error!(msg, kind)
    STDOUT.puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  DecommissionCompilerIca.new(JSON.parse(STDIN.read)).execute!
end
