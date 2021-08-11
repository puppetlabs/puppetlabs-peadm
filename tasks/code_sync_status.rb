#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: code_sync_status
require 'net/https'
require 'uri'
require 'json'
require 'logger'

# Parameters expected:
#   Hash
#     Array requestedenvironments
$params = JSON.parse(STDIN.read)
#$logger = Logger.new(STDOUT)
#$logger.level = ($params['debug']) ? Logger::DEBUG : Logger::INFO

uri = URI.parse('https://localhost:8140/status/v1/services?level=debug')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
response = http.request(Net::HTTP::Get.new(uri.request_uri))
raise "API failure https://localhost:8140/status/v1/services returns #{response.code}" unless response.is_a? Net::HTTPSuccess
servers = JSON.parse(response.body)['file-sync-storage-service']['status']['clients'].keys
environments  = JSON.parse(response.body)['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'].keys()

if params['requestedenvironments'].any?{ |s| s.casecmp("all")==0 }
  puts "Checking all deployed environments"
else
  for environment in params['requestedenvironments']
    if environments.any?{ |s| s.casecmp("#{environment}")==0 }
      puts "Environment #{environment} is visible and will be checked"
# add to some sort of list
    else
      puts "Environment #{environment} is not visible and will not be checked"
    end
  end
end

#if environments contains all ALL or any other combo crack on with the lot
# else
# check our passed in environments do they exist
# if they dont output they dont and remove from list
for environment in environments
  puts environment
  puts '---'
  match = true
  for server in servers do
    puts server
    puts '---'
    servercommit = JSON.parse(response.body)['file-sync-storage-service']['status']['clients']["#{server}"]['repos']['puppet-code']['submodules']["#{environment}"]['latest_commit']['message'][32..71]
    primarycommit = JSON.parse(response.body)['file-sync-storage-service']['status']['repos']['puppet-code']['submodules']["#{environment}"]['latest_commit']['message'][32..71]
# Error check here that it is not the default no code manager message and it at least vageuly looks like a sha1 /\b([a-f0-9]{40})\b/
    puts servercommit
    puts primarycommit
    if servercommit == primarycommit
      puts "#{server} in sync for #{environment}"
    else
      puts "#{server} out of sync for #{environment}"
    end
  end
end


#uri = URI.parse('https://localhost:8140/status/v1/services?level=debug')
#http = Net::HTTP.new(uri.host, uri.port)
#http.use_ssl = true
#http.verify_mode = OpenSSL::SSL::VERIFY_NONE
#request = Net::HTTP::get(uri.request_uri)
#request['Content-Type'] = 'application/json'
#response = http.request(request)
#raise unless response.is_a? Net::HTTPSuccess
#servers = JSON.parse(response.body)['file-sync-storage-service']['status']['clients']
#puts servers
