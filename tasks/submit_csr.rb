#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

#
require 'json'
require 'open3'
require 'puppet'
require 'puppet/face'

# Submit a CSR
class SubmitCSR
  def initialize(params)
    @dns_alt_names = params['dns_alt_names']
  end

  def already_signed?
    cmd = ['/opt/puppetlabs/bin/puppet', 'ssl', 'verify']
    output, status = Open3.capture2e(*cmd)
    STDOUT.puts output
    status.success?
  end

  def execute!
    majver = Gem::Version.new(Puppet.version).segments.first

    if majver < 6
      # signed cert already exist, assuming it is valid, no good way to verify until Puppet 6
      exit 0 if File.exist?(Puppet.settings[:hostcert])
      dns_alt_name_str = @dns_alt_names.nil? ? Puppet.settings[:dns_alt_names] : @dns_alt_names.join(',')
      cmd = ['/opt/puppetlabs/bin/puppet', 'certificate', 'generate',
             '--ca-location', 'remote',
             '--dns-alt-names', dns_alt_name_str,
             Puppet.settings[:certname]]
    else
      exit 0 if already_signed?
      cmd = ['/opt/puppetlabs/bin/puppet', 'ssl', 'submit_request']
      unless @dns_alt_names.nil?
        cmd << '--dns_alt_names' << @dns_alt_names.join(',')
      end
    end

    output, status = Open3.capture2e(*cmd)
    STDOUT.puts output
    if status.success?
      exit 0
    else
      exit 1
    end
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  submit = SubmitCSR.new(JSON.parse(STDIN.read))
  submit.execute!
end
