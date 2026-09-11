#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: query the primary's record of a compiler's ICA state. Runs on
# the primary, querying its own local CA service
# (GET /puppet-ca/v1/intermediate-ca/:fqdn). Used by
# peadm::promote_compiler_to_ica's preflight step to decide whether a CSR
# still needs submitting.
class GetIcaState
  def initialize(params)
    @compiler_fqdn = params.fetch('compiler_fqdn')
  end

  def execute!
    https = IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)
    res = https.get("/puppet-ca/v1/intermediate-ca/#{@compiler_fqdn}")

    case res.code
    when '200'
      STDOUT.puts(JSON.parse(res.body).to_json)
    when '404'
      # No ICA has ever been requested for this compiler. Distinct from any
      # terminal state (pending/active/rejected/...) the primary tracks once
      # a request exists, and not itself an error.
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
