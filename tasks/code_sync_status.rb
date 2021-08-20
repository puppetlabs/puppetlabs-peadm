#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: code_sync_status
require 'net/https'
require 'uri'
require 'json'
require 'puppet'

# CodeSyncStatus task class
class CodeSyncStatus
  def initialize(params)
    @params = params
  end

  def execute!
    puts syncstatus.to_json
  end

  def https
    https = Net::HTTP.new('localhost', '8140')
    https.use_ssl = true
    https.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE
    https
  end

  def apistatus
    status = https
    # Only debug level includes code sync details
    status_request = Net::HTTP::Get.new('/status/v1/services?level=debug')
    JSON.parse(status.request(status_request).body)
  end

  def checkenvironmentlist(environments, requestedenvironments)
    environmentstocheck = []
    # If all was passed as an argument we check all visible environments
    if requestedenvironments.any? { |s| s.casecmp('all') == 0 }
      environmentstocheck = environments
    # Else check each requested environment to confirm its a visible environment
    else
      requestedenvironments.each do |environment|
        environments.any? { |s| s.casecmp(environment.to_s) == 0 } || raise("Environment #{environment} is not visible and will not be checked")
        environmentstocheck << environment
      end
    end
    environmentstocheck
  end

  def checkenvironmentcode(environment, servers, statuscall)
    # Find the commit ID of the environment according to the file sync service
    primarycommit = statuscall['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'][environment.to_s]['latest_commit']['message'][32..71]
    results = {}
    results['latest_commit'] = primarycommit
    servers.each do |server|
      results[server] = {}
      # Find the commit ID of the server we are checking for this environment
      servercommit = statuscall['file-sync-storage-service']['status']['clients'][server.to_s]['repos']['puppet-code']['submodules'][environment.to_s]['latest_commit']['message'][32..71]
      results[server]['commit'] = servercommit
      # Check if it matches and if not mark the environment not in sync on an environment
      results[server]['sync'] = servercommit == primarycommit
    end
    results['sync'] = results.all? { |_k, v| v['sync'] == true }
    results
  end

  def syncstatus
    statuscall = apistatus
    # Get list of servers from filesync service
    servers = statuscall['file-sync-storage-service']['status']['clients'].keys
    # Get list of environments from filesync service
    environments = statuscall['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'].keys
    # Process this list of environments and validate against visible environments
    environmentstocheck = checkenvironmentlist(environments, @params['environments'])
    results = {}
    # For each environment get the syncronisation information of the servers
    environmentstocheck.each do |environment|
      results[environment] = checkenvironmentcode(environment, servers, statuscall)
    end
    # Confirm are all environments being checked in sync
    results['sync'] = results.all? { |_k, v| v['sync'] == true }
    results
  end
end
# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = CodeSyncStatus.new(JSON.parse(STDIN.read))
  task.execute!
end
