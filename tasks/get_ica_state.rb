#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: query the primary's record of a compiler's ICA state. Runs on
# the primary, querying its own local CA service
# (GET /puppet-ca/v1/intermediate-ca/:fqdn).
class GetIcaState
  # This endpoint only ever surfaces the *live* ICA for an fqdn, so a 200
  # body's state can only ever be one of these two -- asserted explicitly
  # rather than trusted, so a future protocol change or version skew
  # doesn't silently hand the caller a state it has no filter for.
  VALID_LIVE_STATES = ['active', 'draining'].freeze

  def initialize(params)
    @compiler_fqdn = params.fetch('compiler_fqdn')
  end

  def execute!
    IcaTaskHelper.validate_fqdn!(@compiler_fqdn)
    https = IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)
    res = https.get("/puppet-ca/v1/intermediate-ca/#{@compiler_fqdn}")

    case res.code
    when '200'
      body = JSON.parse(res.body)
      unless VALID_LIVE_STATES.include?(body['state'])
        raise "Unexpected ICA state '#{body['state']}' for #{@compiler_fqdn}: expected one of #{VALID_LIVE_STATES.join(', ')}"
      end

      STDOUT.puts(body.to_json)
    when '404'
      # This endpoint only ever shows the live ICA for an fqdn -- the
      # primary returns 404 both when no ICA was ever provisioned and once
      # one has moved to revoked/decommissioned, so 'none' here covers both
      # rather than only the former. Not itself an error either way: both
      # cases mean there is nothing left to demote.
      STDOUT.puts({ 'state' => 'none' }.to_json)
    else
      raise "Failed to query ICA state for #{@compiler_fqdn}: HTTP #{res.code} - #{res.body}"
    end
    exit 0
  rescue StandardError => e
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/get_ica_state_failed' } }.to_json)
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  GetIcaState.new(JSON.parse(STDIN.read)).execute!
end
