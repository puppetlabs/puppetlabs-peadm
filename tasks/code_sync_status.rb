#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: code_sync_status
require 'net/https'
require 'uri'
require 'json'
require 'fileutils'

# Parameters expected:
#   Hash
#     Array requestedenvironments

uri = URI.parse('https://localhost:8140/status/v1/services?level=debug')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
response = http.request(Net::HTTP::Get.new(uri.request_uri))
raise "API failure https://localhost:8140/status/v1/services returns #{response.code}" unless response.is_a? Net::HTTPSuccess
#enivronments = reponse.body['filesync-storage-service']['status']['clients'][server]['repos']['puppet-code']['submodules'].keys()
servers = JSON.parse(response.body)['file-sync-storage-service']['status']['clients'].keys
environments  = JSON.parse(response.body)['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'].keys()
for server in servers do
  puts server
  puts '---'
  for environment in environments
    puts environment
    servercommit = JSON.parse(response.body)['file-sync-storage-service']['status']['clients']["#{server}"]['repos']['puppet-code']['submodules']["#{environment}"]['latest_commit']['message']
    puts servercommit
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