#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

#
require 'json'
require 'open3'
require 'puppet'
require 'puppet/face'

Puppet.initialize_settings

def already_signed?
  cmd = ['/opt/puppetlabs/bin/puppet', 'ssl', 'verify']
  _, status = Open3.capture2(*cmd)
  status.success?
end

def main
  majver = Gem::Version.new(Puppet.version).segments.first
  if majver < 6
    # signed cert already exist, assuming it is valid, no good way to verify until Puppet 6
    exit 0 if File.exist?(Puppet.settings[:hostcert])
    cmd = ['/opt/puppetlabs/bin/puppet', 'certificate', 'generate',
           '--ca-location', 'remote',
           '--dns-alt-names', Puppet.settings[:dns_alt_names],
           Puppet.settings[:certname]]
  else
    exit 0 if already_signed?
    cmd = ['/opt/puppetlabs/bin/puppet', 'ssl', 'submit_request']
  end

  stdout, status = Open3.capture2(*cmd)
  puts stdout
  if status.success?
    exit 0
  else
    exit 1
  end
end

main
