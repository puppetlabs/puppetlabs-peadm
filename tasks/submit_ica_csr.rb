#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'puppet'
require_relative '../files/ica_task_helper'

# Bolt task: generate and submit this compiler's ICA CSR to the PE primary.
# All cryptography is delegated to the puppetserver ICA provisioning
# subcommand; this task only invokes it and returns its result. Makes no
# change to bootstrap.cfg and restarts no services.
class SubmitIcaCsr
  def initialize(_params); end

  def execute!
    if IcaTaskHelper.promoted_to_ica?
      STDOUT.puts({ 'already-promoted' => true }.to_json)
      exit 0
    end

    stdout, stderr, status = IcaTaskHelper.run_ica_provision

    if status.success?
      # A successful provision can still have something to say: the
      # subcommand may warn without failing (for example if the agent trust
      # bundle looks incomplete). stderr is otherwise only surfaced in the
      # failure branch below, so without this any warning from a successful
      # run is discarded and never reaches the operator. Emitted before the
      # result so it cannot be lost behind the task's own output.
      warn stderr unless stderr.to_s.empty?

      begin
        request = JSON.parse(stdout)
        STDOUT.puts({ 'request-id' => request.fetch('request-id') }.to_json)
        exit 0
      rescue JSON::ParserError, KeyError => e
        error_msg = "ICA CSR submission: invalid subcommand response (#{e.class}: #{e.message}). Raw output: #{stdout}"
        IcaTaskHelper.emit_error!(error_msg, 'peadm/submit_ica_csr_failed')
        exit 1
      end
    else
      warn stderr
      IcaTaskHelper.emit_error!("ICA CSR submission failed: #{stderr}", 'peadm/submit_ica_csr_failed')
      exit 1
    end
  rescue StandardError => e
    # The ICA provisioning subcommand may not exist on every puppetserver yet,
    # so an unstructured failure (Errno::ENOENT and friends) is realistic.
    # Report it through the task's own _error contract rather than a raw
    # backtrace, but still log the backtrace to stderr for whoever is
    # watching the run: the _error message alone can be too thin to debug an
    # unexpected failure from.
    warn "#{e.class}: #{e.message}"
    warn e.backtrace.first(10).join("\n") if e.backtrace
    IcaTaskHelper.emit_error!(e.message, 'peadm/submit_ica_csr_failed')
    exit 1
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  SubmitIcaCsr.new(JSON.parse(STDIN.read)).execute!
end
