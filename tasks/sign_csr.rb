#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'puppet'

# Class to run and execute the `puppetserver ca sign` command as a task.
class SignCSR
  class SigningError; end

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
    rescue SigningError
      exit 1 if attempts > 5
      attempts += 1
      puts "Signing attempt #{attempts} failed; waiting 1s and trying again"
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

    stdout, status = Open3.capture2(*cmd)
    puts stdout
    raise SigningError unless status.success?
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  task = SignCSR.new(JSON.parse(STDIN.read))
  task.execute!
end
