#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'socket'
require 'timeout'
require_relative '../files/ica_task_helper'

# Bolt task: probe candidate primary FQDNs and report the first reachable one.
# Decision S. Runs on the compiler being promoted: the primary is the host
# that just stopped answering, and the compiler is the one target the calling
# plan already knows is healthy (it just ran submit_ica_csr there). Read-only,
# idempotent, and owns no retry loop of its own -- peadm::poll_ica_approval
# calls this again on its own polling cadence.
class ResolveCurrentPrimary
  CONNECT_TIMEOUT_SECONDS = 10

  # Only treat expected network-level failures as "unreachable". A narrower
  # rescue than StandardError here matters: candidates are tried in a silent
  # loop with no per-candidate logging, so a programming error (a typo'd
  # constant, a NoMethodError) would otherwise be indistinguishable from a
  # genuinely down host and get reported as "no-reachable-candidate" instead
  # of surfacing as the task failure it actually is.
  UNREACHABLE_ERRORS = [
    Timeout::Error,
    SocketError,
    IOError,
    Errno::ECONNREFUSED,
    Errno::ETIMEDOUT,
    Errno::EHOSTUNREACH,
    Errno::ENETUNREACH,
    Errno::ECONNRESET,
    Errno::EHOSTDOWN,
    Errno::ENETDOWN,
  ].freeze

  def initialize(params)
    @candidates = params.fetch('candidates')
  end

  def execute!
    resolved_from = @candidates.find { |candidate| reachable?(candidate) }

    if resolved_from
      STDOUT.puts({
        'primary_url'   => "https://#{resolved_from}:#{IcaTaskHelper::CA_SERVICE_PORT}",
        'resolved_from' => resolved_from,
      }.to_json)
    else
      STDOUT.puts({ 'error' => 'no-reachable-candidate' }.to_json)
    end
    exit 0
  rescue StandardError => e
    STDOUT.puts({ '_error' => { 'msg' => e.message, 'kind' => 'peadm/resolve_current_primary_failed' } }.to_json)
    exit 1
  end

  private

  def reachable?(candidate)
    Timeout.timeout(CONNECT_TIMEOUT_SECONDS) do
      TCPSocket.new(candidate, IcaTaskHelper::CA_SERVICE_PORT).close
    end
    true
  rescue *UNREACHABLE_ERRORS
    false
  end
end

unless ENV['RSPEC_UNIT_TEST_MODE']
  ResolveCurrentPrimary.new(JSON.parse(STDIN.read)).execute!
end
