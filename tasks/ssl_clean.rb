#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'puppet'
require 'open3'

def main
  certname = JSON.parse(STDIN.read)['certname']
  majver = Gem::Version.new(Puppet.version).segments.first
  if majver < 6
    puts "Deleting #{certname}.pem files..."
    Dir.glob("/etc/puppetlabs/puppet/ssl/**/#{certname}.pem").each do |file|
      File.delete(file)
    end
    puts 'Done'
    exit 0
  else
    cmd = ['/opt/puppetlabs/bin/puppet', 'ssl', 'clean', '--certname', certname]
    stdout, status = Open3.capture2(*cmd)
    puts stdout
    if status.success?
      exit 0
    else
      exit 1
    end
  end
end

main
