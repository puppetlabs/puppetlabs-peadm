#!/opt/puppetlabs/puppet/bin/ruby
#
# rubocop:disable Style/GlobalVars
require 'json'
require 'open3'

def main
  params = JSON.parse(STDIN.read)

  cmd = ['/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
         '--certname', params['certnames'].join(',')]

  stdout, status = Open3.capture2(*cmd)
  puts stdout
  if status.success?
    exit 0
  else
    exit 1
  end
end

main
