#!/opt/puppetlabs/puppet/bin/ruby

require 'json'

begin
  params  = JSON.parse(STDIN.read)
  content = File.read(params['path'])
rescue StandardError => err
  result = {
    'content' => nil,
    'error'   => err.message,
  }
else
  result = {
    'content' => content,
  }
ensure
  puts result.to_json
end
