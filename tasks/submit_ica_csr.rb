#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: generate and submit this compiler's ICA CSR to the PE primary.
# PE-44791 / Phase 3 plan ticket 7.3. All cryptography is delegated to the
# puppetserver ICA provisioning subcommand (ticket 7.1 / PE-44789); this task
# only invokes it and returns its result. Makes no change to bootstrap.cfg
# and restarts no services.
class SubmitIcaCsr
  def initialize(_params); end

  def execute!
    if IcaTaskHelper.promoted_to_ica?
      STDOUT.puts({ 'already-promoted' => true }.to_json)
      exit 0
    end

    stdout, stderr, status = IcaTaskHelper.run_ica_provision

    if status.success?
      begin
        request = JSON.parse(stdout)
        STDOUT.puts({ 'request-id' => request.fetch('request-id') }.to_json)
        exit 0
      rescue JSON::ParserError, KeyError => e
        error_msg = "ICA CSR submission: invalid subcommand response (#{e.class}: #{e.message}). Raw output: #{stdout}"
        STDOUT.puts({ '_error' => { 'msg' => error_msg, 'kind' => 'peadm/submit_ica_csr_failed' } }.to_json)
        exit 1
      end
    else
      warn stderr
      STDOUT.puts({ '_error' => { 'msg' => "ICA CSR submission failed: #{stderr}", 'kind' => 'peadm/submit_ica_csr_failed' } }.to_json)
      exit 1
    end
  rescue StandardError => e
    # The ICA provisioning subcommand may not exist on every puppetserver yet,
    # so an unstructured failure (Errno::ENOENT and friends) is realistic.
    # Report it through the task's own _error contract rather than a backtrace.
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/submit_ica_csr_failed' } }.to_json)
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  SubmitIcaCsr.new(JSON.parse(STDIN.read)).execute!
end
