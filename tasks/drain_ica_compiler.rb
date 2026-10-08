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
    response = https.request(request)

    unless response.code == '200'
      IcaTaskHelper.fail!("Failed to drain Intermediate CA for #{@compiler_fqdn}: HTTP #{response.code} - #{response.body}", 'peadm/drain_ica_compiler_failed')
    end

    STDOUT.puts(
      "Compiler #{@compiler_fqdn} ICA is now draining. Proxy compilers will exclude it within the next pool " \
      'refresh interval.',
    )
    exit 0
  rescue *IcaTaskHelper::LOCAL_FILE_ERROR_CLASSES => e
    IcaTaskHelper.fail!("Failed to read a required local file: #{e.message}", 'peadm/drain_ica_compiler_local_file_error')
  rescue *IcaTaskHelper::CONNECTION_ERROR_CLASSES => e
    msg, suffix = IcaTaskHelper.classify_connection_error(e)
    IcaTaskHelper.fail!(msg, "peadm/drain_ica_compiler_#{suffix}")
  rescue StandardError => e
    IcaTaskHelper.fail!(e.message, 'peadm/drain_ica_compiler_failed')
  end

  private

  def request
    IcaTaskHelper.build_intermediate_ca_request(Net::HTTP::Post, @compiler_fqdn, @token_file, action: 'drain')
  end

  def https
    IcaTaskHelper.primary_https_client(Puppet.settings[:certname], IcaTaskHelper::CA_SERVICE_PORT)
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  DrainIcaCompiler.new(JSON.parse(STDIN.read)).execute!
end
