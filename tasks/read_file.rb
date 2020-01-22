#!/opt/puppetlabs/puppet/bin/ruby

require 'json'

params  = JSON.parse(STDIN.read)
content = File.read(params['path'])
result  = { 'content' => content }.to_json

puts result
