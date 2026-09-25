#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: emergency-revoke a compiler's Intermediate CA. Runs on the
# primary. POSTs /puppet-ca/v1/intermediate-ca/:fqdn/revoke, which -- unlike
# every other primary-side route peadm calls -- carries no certname
# allowance (puppet-enterprise-modules' tk_authz.pp gates it on certificate_authority:sign_ica alone),
# so this task authenticates with both this node's own agent certificate
# (mTLS transport, via IcaTaskHelper.primary_https_client) and an RBAC token
# read from token_file, forwarded as X-Authentication -- the same dual-auth
# shape peadm::puppet_infra_upgrade already uses against the orchestrator.
#
# Revoking splices the ICA's own certificate serial into the root CRL,
# which is what invalidates every agent certificate that ICA signed. A 200
# with "crl-updated": false means the ICA is marked revoked in storage but
# the splice itself failed -- nothing is actually invalidated yet, so
# reporting success here would tell an operator agent certs are revoked
# when they are not. That case is treated as a failure rather than passed
# through.
class RevokeCompilerIca
  def initialize(params)
    @compiler_fqdn = params.fetch('compiler_fqdn')
    @token_file = params['token_file']
  end

  def execute!
    IcaTaskHelper.validate_fqdn!(@compiler_fqdn)
    response = https.request(revoke_request)

    unless response.code == '200'
      error!("Failed to revoke Intermediate CA for #{@compiler_fqdn}: HTTP #{response.code} - #{response.body}", 'peadm/revoke_compiler_ica_failed')
    end

    body = JSON.parse(response.body)
    unless body['crl-updated']
      error!(
        "Intermediate CA for #{@compiler_fqdn} was marked revoked, but the root CRL was not updated -- " \
        'agent certificates it signed are NOT yet invalidated. Investigate the CRL before treating this ICA as revoked.',
        'peadm/revoke_compiler_ica_crl_not_updated',
      )
    end

    STDOUT.puts(body.to_json)
    exit 0
  rescue StandardError => e
    error!(e.message, 'peadm/revoke_compiler_ica_failed')
  end

  private

  def revoke_request
    req = Net::HTTP::Post.new("/puppet-ca/v1/intermediate-ca/#{@compiler_fqdn}/revoke")
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
  RevokeCompilerIca.new(JSON.parse(STDIN.read)).execute!
end
