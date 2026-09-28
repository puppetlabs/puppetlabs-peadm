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
    response = https.request(request)

    unless response.code == '200'
      IcaTaskHelper.fail!("Failed to revoke Intermediate CA for #{@compiler_fqdn}: HTTP #{response.code} - #{response.body}", 'peadm/revoke_compiler_ica_failed')
    end

    body = JSON.parse(response.body)
    unless body['crl-updated']
      IcaTaskHelper.fail!(
        "Intermediate CA for #{@compiler_fqdn} was marked revoked, but the root CRL was not updated -- " \
        'agent certificates it signed are NOT yet invalidated. Investigate the CRL before treating this ICA as revoked.',
        'peadm/revoke_compiler_ica_crl_not_updated',
      )
    end

    STDOUT.puts(body.to_json)
    exit 0
  rescue *IcaTaskHelper::CONNECTION_ERROR_CLASSES => e
    msg, suffix = IcaTaskHelper.classify_connection_error(e)
    IcaTaskHelper.fail!(msg, "peadm/revoke_compiler_ica_#{suffix}")
  rescue JSON::ParserError => e
    IcaTaskHelper.fail!("Invalid response body from the primary: #{e.message}", 'peadm/revoke_compiler_ica_invalid_response')
  rescue StandardError => e
    IcaTaskHelper.fail!(e.message, 'peadm/revoke_compiler_ica_failed')
  end

  private

  def request
    IcaTaskHelper.build_intermediate_ca_request(Net::HTTP::Post, @compiler_fqdn, @token_file, action: 'revoke')
  end

  def https
    IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  RevokeCompilerIca.new(JSON.parse(STDIN.read)).execute!
end
