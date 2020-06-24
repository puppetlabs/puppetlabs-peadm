#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

#
require 'json'
require 'open3'

def main
  params  = JSON.parse(STDIN.read)
  type    = params['type']
  targets = params['targets']

  exit 0 if targets.empty?

  cmd = ['/opt/puppetlabs/bin/puppet-infrastructure', '--render-as', 'json', 'upgrade']
  cmd << '--token-file' << params['token_file'] unless params['token_file'].nil?
  cmd << type << targets.join(',')

  stdouterr, status = Open3.capture2e(*cmd)
  puts stdouterr
  if status.success?
    exit 0
  else
    exit 1
  end
end

main
