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
    conf = %x{/opt/puppetlabs/bin/puppet config print dns_alt_names certname}
             .chomp
             .split("\n")
             .map {|line| line.split(' = ') }
             .to_h

    cmd = ['/opt/puppetlabs/bin/puppet', 'certificate', 'generate',
           '--ca-location', 'remote',
           '--dns-alt-names', conf['dns_alt_names'],
           conf['certname']
          ]
  else
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
