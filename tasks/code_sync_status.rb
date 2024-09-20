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
    puts sync_status.to_json
  end

  private

  def https_client
    client = Net::HTTP.new(Puppet.settings[:certname], 8140)
    client.use_ssl = true
    client.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    client.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    client.verify_mode = OpenSSL::SSL::VERIFY_PEER
    client.ca_file = Puppet.settings[:localcacert]
    client
  end

  def api_status
    status = https_client
    # Only debug level includes code sync details
    status_request = Net::HTTP::Get.new('/status/v1/services?level=debug')
    JSON.parse(status.request(status_request).body)
  end

  def check_environment_list(environments, request_environments)
    environmentstocheck = []
    # If all was passed as an argument we check all visible environments
    if request_environments.any? { |s| s.casecmp('all') == 0 }
      environmentstocheck = environments
    # Else check each requested environment to confirm its a visible environment
    else
      request_environments.each do |environment|
        environments.any? { |s| s.casecmp(environment.to_s) == 0 } || raise("Environment #{environment} is not visible and will not be checked")
        environmentstocheck << environment
      end
    end
    environmentstocheck
  end

  def check_environment_code(environment, servers, status_call)
    # Find the commit ID of the environment according to the file sync service note expected message is of the format
    # code-manager deploy signature: '93027145096d9f1e0b716b20b8129618d0a2c7e2'
    primarycommit = status_call.dig('file-sync-storage-service',
                                    'status',
                                    'repos',
                                    'puppet-code',
                                    'submodules',
                                    environment.to_s,
                                    'latest_commit',
                                    'message').split("'").last
    results = {}
    results['latest_commit'] = primarycommit
    results['servers'] = {}
    servers.each do |server|
      results['servers'][server] = {}
      # Find the commit ID of the server we are checking for this environment note expected message is of the format
      # code-manager deploy signature: '93027145096d9f1e0b716b20b8129618d0a2c7e2'
      servercommit = status_call.dig('file-sync-storage-service',
                                     'status',
                                     'clients',
                                     server.to_s,
                                     'repos',
                                     'puppet-code',
                                     'submodules',
                                     environment.to_s,
                                     'latest_commit',
                                     'message').split("'").last
      results['servers'][server]['commit'] = servercommit
      # Check if it matches and if not mark the environment not in sync on an environment
      results['servers'][server]['sync'] = servercommit == primarycommit
    end
    results['sync'] = results['servers'].all? { |_k, v| v['sync'] == true }
    results
  end

  def sync_status
    status_call = api_status
    # Get list of servers from filesync service
    servers = status_call['file-sync-storage-service']['status']['clients'].keys
    # Get list of environments from filesync service
    environments = status_call['file-sync-storage-service']['status']['repos']['puppet-code']['submodules'].keys
    # Process this list of environments and validate against visible environments
    environmentstocheck = check_environment_list(environments, @params['environments'])
    results = {}
    # For each environment get the syncronisation information of the servers
    environmentstocheck.each do |environment|
      results[environment] = check_environment_code(environment, servers, status_call)
    end

    # Confirm are all environments being checked in sync
    {
      'environments' => results,
      'sync' => results.all? { |_k, v| v['sync'] == true },
    }
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
