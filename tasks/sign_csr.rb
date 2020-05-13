#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

#
require 'json'
require 'open3'
require 'puppet'

def csr_signed?(certname)
  !File.exist?(File.join(Puppet.settings[:csrdir], "#{certname}.pem")) &&
    File.exist?(File.join(Puppet.settings[:cadir], 'signed', "#{certname}.pem"))
end

def main
  Puppet.initialize_settings
  params = JSON.parse(STDIN.read)
  unsigned = params['certnames'].reject { |name| csr_signed?(name) }

  exit 0 if unsigned.empty?

  cmd = ['/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
         '--certname', unsigned.join(',')]

  stdout, status = Open3.capture2(*cmd)
  puts stdout
  if status.success?
    exit 0
  else
    exit 1
  end
end

main
