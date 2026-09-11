#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: query the primary's fleet-wide autosign consistency flag. Runs
# on the primary, querying its own local CA service
# (GET /puppet-ca/v1/intermediate-ca). Used by peadm::promote_compiler_to_ica's
# preflight step to warn (not fail) an operator promoting into a fleet already
# in autosign disagreement.
class GetAutosignConsistency
  def initialize(_params); end

  def execute!
    https = IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)
    res = https.get('/puppet-ca/v1/intermediate-ca')

    unless res.code == '200'
      raise "Failed to query autosign consistency: HTTP #{res.code} - #{res.body}"
    end

    body = JSON.parse(res.body)
    STDOUT.puts({ 'autosign-inconsistent' => body['autosign-inconsistent'] == true }.to_json)
    exit 0
  rescue StandardError => e
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/get_autosign_consistency_failed' } }.to_json)
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  GetAutosignConsistency.new(JSON.parse(STDIN.read)).execute!
end
