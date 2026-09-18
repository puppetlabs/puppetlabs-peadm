#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'puppet'

# Class to run and execute the `puppetserver ca sign` command as a task.
class SignCSR
  class SigningError < StandardError; end

  def initialize(params)
    Puppet.initialize_settings
    @certnames = params['certnames']
  end

  def execute!
    attempts = 0

    begin
      unsigned = @certnames.reject { |name| csr_signed?(name) }
      exit 0 if unsigned.empty?
      sign(unsigned)
    rescue SigningError => e
      # The 1s backoff, 6-retry bound (7 total attempts), and lack of
      # transient-vs-permanent failure differentiation are known
      # simplifications -- revisit if puppetserver ca sign failures prove to
      # need longer backoff or finer-grained handling in practice.
      attempts += 1
      if attempts > 6
        warn "Signing failed after #{attempts} attempts, giving up: #{e.message}"
        exit 1
      end
      puts "Signing attempt #{attempts} failed (#{e.message}); waiting 1s and trying again"
      sleep 1
      retry
    end
  end

  def csr_signed?(certname)
    !File.exist?(File.join(Puppet.settings[:csrdir], "#{certname}.pem")) &&
      File.exist?(File.join(Puppet.settings[:cadir], 'signed', "#{certname}.pem"))
  end

  def sign(certnames)
    cmd = ['/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
           '--certname', certnames.join(',')]

    output, status = Open3.capture2e(*cmd)
    puts output
    return if status.success?

    # Collapsed to one line so the per-retry/give-up log lines that embed
    # this message stay grep-able even when puppetserver's own output (now
    # stdout+stderr merged via capture2e) spans multiple lines. scrub first:
    # gsub raises ArgumentError on invalid byte sequences, which would
    # otherwise let a garbled subprocess output byte crash this formatting
    # step itself and bypass the retry loop entirely.
    single_line_output = output.scrub('?').gsub(%r{\s*\n\s*}, ' ').strip
    raise SigningError, "puppetserver ca sign exited #{status.exitstatus}: #{single_line_output}"
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  task = SignCSR.new(JSON.parse(STDIN.read))
  task.execute!
end
