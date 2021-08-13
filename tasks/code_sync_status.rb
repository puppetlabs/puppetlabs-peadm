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
environments  = JSON.parse(response.body)['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'].keys()
environmentstocheck = Array.new

# If all was passed as an argument we check all visible environments
if params['environments'].any?{ |s| s.casecmp("all")==0 }
  environmentstocheck = environments
# Else check each requested environment to confirm its a visible environment
else
  for environment in params['environments']
    if environments.any?{ |s| s.casecmp("#{environment}")==0 }
      environmentstocheck << environment
    else
      raise "Environment #{environment} is not visible and will not be checked"
    end
  end
end
results = {}
# Run status of the script assume its good until it we hit a failure
scriptstatus = true
for environment in environmentstocheck
  results[environment] = {}
  # The status of this environment assume its good until we hit a failure
  environmentmatch = true
  # Find the commit ID of the environment accroding to the file sync service
  primarycommit = JSON.parse(response.body)['file-sync-storage-service']['status']['repos']['puppet-code']['submodules']["#{environment}"]['latest_commit']['message'][32..71]
  results[environment]['latest_commit'] = primarycommit
  for server in servers do
    results[environment][server] = {}
    # Find the commit ID of the server we are checking for this environment 
    servercommit = JSON.parse(response.body)['file-sync-storage-service']['status']['clients']["#{server}"]['repos']['puppet-code']['submodules']["#{environment}"]['latest_commit']['message'][32..71]   
    # Error check here that it is not the default no code manager message and it at least vageuly looks like a sha1 /\b([a-f0-9]{40})\b/
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
  if environmentmatch
    results [environment]['in_sync'] = true
  else
    results [environment]['in_sync'] = false
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