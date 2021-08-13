#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: code_sync_status
require 'net/https'
require 'uri'
require 'json'

# Parameters expected:
#   Hash
#     Array requestedenvironments
params = JSON.parse(STDIN.read)

# Only debug level includes code sync details
uri = URI.parse('https://localhost:8140/status/v1/services?level=debug')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
response = http.request(Net::HTTP::Get.new(uri.request_uri))
# Fail with return code
raise "API failure https://localhost:8140/status/v1/services returns #{response.code}" unless response.is_a? Net::HTTPSuccess
# Get list of servers from filesync service
servers = JSON.parse(response.body)['file-sync-storage-service']['status']['clients'].keys
# Get list of environments from filesync service
environments = JSON.parse(response.body)['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'].keys
environmentstocheck = []

# If all was passed as an argument we check all visible environments
if params['environments'].any? { |s| s.casecmp('all') == 0 }
  environmentstocheck = environments
# Else check each requested environment to confirm its a visible environment
else
  params['environments'].each do |environment|
    environments.any? { |s| s.casecmp(environment.to_s) == 0 } || raise("Environment #{environment} is not visible and will not be checked")
    environmentstocheck << environment
  end
end
results = {}
# Run status of the script assume its good until it we hit a failure
scriptstatus = true
environmentstocheck.each do |environment|
  results[environment] = {}
  # The status of this environment assume its good until we hit a failure
  environmentmatch = true
  # Find the commit ID of the environment accroding to the file sync service
  primarycommit = JSON.parse(response.body)['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'][environment.to_s]['latest_commit']['message'][32..71]
  results[environment]['latest_commit'] = primarycommit
  servers.each do |server|
    results[environment][server] = {}
    # Find the commit ID of the server we are checking for this environment
    servercommit = JSON.parse(response.body)['file-sync-storage-service']['status']['clients'][server.to_s]['repos']['puppet-code']['submodules'][environment.to_s]['latest_commit']['message'][32..71]
    results [environment][server]['commit'] = servercommit
    # Check if it matches and if not mark the environment and script as having a server not in sync on an environment
    if servercommit == primarycommit
      results [environment][server]['sync'] = true
    else
      results [environment][server]['sync'] = false
      environmentmatch = false
      scriptstatus = false
    end
  end
  # write to the result json if its a match for the environment
  results [environment]['in_sync'] = if environmentmatch
                                       true
                                     else
                                       false
                                     end
end
# Write to the result json if for all environments checked if its a match
if scriptstatus
  results['in_sync'] = true
  puts results.to_json
  exit 0
else
  results['in_sync'] = false
  puts results.to_json
  exit 1
end
