#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'puppet'
require 'open3'

def main
  certname = JSON.parse(STDIN.read)['certname']
  majver = Gem::Version.new(Puppet.version).segments.first
  if majver < 6
    cmd = ['/opt/puppetlabs/bin/puppet', 'certificate', 'find', '--ca-location', 'remote', certname]
  else
    cmd = ['/opt/puppetlabs/bin/puppet', 'ssl', 'download_cert', '--certname', certname]
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
