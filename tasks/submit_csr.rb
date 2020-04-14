#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

#
require 'json'
require 'open3'

def already_signed?
  cmd = ['/opt/puppetlabs/bin/puppet', 'ssl', 'verify']
  _, status = Open3.capture2(*cmd)
  status.success?
end

def main
  majver = `/opt/puppetlabs/bin/puppet --version`
           .chomp
           .split('.')
           .first
           .to_i

  if majver < 6
    conf = `/opt/puppetlabs/bin/puppet config print dns_alt_names certname`
           .chomp
           .split("\n")
           .map { |line| line.split(' = ', 2) }
           .to_h

    cmd = ['/opt/puppetlabs/bin/puppet', 'certificate', 'generate',
           '--ca-location', 'remote',
           '--dns-alt-names', conf['dns_alt_names'],
           conf['certname']]
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
