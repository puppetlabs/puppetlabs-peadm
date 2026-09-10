#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: fetch the status of a pending ICA request from the primary. Thin
# wrapper over GET /puppet-ca/v1/intermediate-ca/requests/:id (SPEC.md sec
# 3.2). This endpoint authenticates with mTLS only -- the request UUID is
# itself the authorization -- so the poll loop in peadm::poll_ica_approval
# needs no privileged credential.
#
# A 404 is reported through the task's own _error contract with a distinct
# 'kind' (peadm/ica_request_not_found) rather than as a generic HTTP failure,
# so the calling plan can tell "the request genuinely does not exist" (a hard
# error) apart from a connection-level failure against this target (which
# should trigger primary-failover resolution instead, per Decision S).
class GetRequestStatus
  def initialize(params)
    @request_id = params.fetch('request_id')
  end

  def execute!
    https = IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)
    res = https.get("/puppet-ca/v1/intermediate-ca/requests/#{@request_id}")

    case res.code
    when '200'
      STDOUT.puts(JSON.parse(res.body).to_json)
      exit 0
    when '404'
      STDOUT.puts({ '_error' => { 'msg' => "No such ICA request: #{@request_id}", 'kind' => 'peadm/ica_request_not_found' } }.to_json)
      exit 1
    else
      raise "Failed to query ICA request status for #{@request_id}: HTTP #{res.code} - #{res.body}"
    end
  rescue StandardError => e
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/get_request_status_failed' } }.to_json)
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  GetRequestStatus.new(JSON.parse(STDIN.read)).execute!
end
