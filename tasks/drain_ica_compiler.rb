#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: begin graceful removal of a compiler's Intermediate CA. Runs on
# the primary. POSTs /puppet-ca/v1/intermediate-ca/:fqdn/drain, transitioning
# an active ICA to draining -- proxy compilers stop routing CSRs to it within
# one pool refresh interval, but nothing is invalidated yet. Gated on
# certificate_authority:sign_ica with no certname allowance (same as revoke
# and decommission), so this task authenticates the same dual way: this
# node's own agent certificate over mTLS, plus an RBAC token read from
# token_file and forwarded as X-Authentication.
class DrainIcaCompiler
  def initialize(params)
    @compiler_fqdn = params.fetch('compiler_fqdn')
    @token_file = params['token_file']
  end

  def execute!
    IcaTaskHelper.validate_fqdn!(@compiler_fqdn)
    response = https.request(drain_request)

    unless response.code == '200'
      error!("Failed to drain Intermediate CA for #{@compiler_fqdn}: HTTP #{response.code} - #{response.body}", 'peadm/drain_ica_compiler_failed')
    end

    STDOUT.puts(
      "Compiler #{@compiler_fqdn} ICA is now draining. Proxy compilers will exclude it within the next pool " \
      'refresh interval.',
    )
    exit 0
  rescue StandardError => e
    error!(e.message, 'peadm/drain_ica_compiler_failed')
  end

  private

  def drain_request
    req = Net::HTTP::Post.new("/puppet-ca/v1/intermediate-ca/#{@compiler_fqdn}/drain")
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
  DrainIcaCompiler.new(JSON.parse(STDIN.read)).execute!
end
