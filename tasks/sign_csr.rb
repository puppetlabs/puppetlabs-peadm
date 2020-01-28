#!/opt/puppetlabs/puppet/bin/ruby
#
# rubocop:disable Style/GlobalVars
require 'json'
require 'open3'

def main
  params = JSON.parse(STDIN.read)
  majver = %x{/opt/puppetlabs/bin/puppet --version}
             .chomp
             .split('.')
             .first
             .to_i

  if majver < 6
    cmd = ['/opt/puppetlabs/bin/puppet', 'cert', 'sign',
           '--allow-dns-alt-names', *params['certnames']]
  else
    cmd = ['/opt/puppetlabs/bin/puppetserver', 'ca', 'sign',
           '--certname', params['certnames'].join(',')]
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
