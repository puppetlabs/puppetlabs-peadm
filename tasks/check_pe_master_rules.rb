#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'net/https'
require 'puppet'

# CheckPeMasterRules task class
class CheckPeMasterRules
  def initialize(params)
    @params = params
  end

  def https_client
    client = Net::HTTP.new(Puppet.settings[:certname], 4433)
    client.use_ssl = true
    client.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    client.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    client.verify_mode = OpenSSL::SSL::VERIFY_PEER
    client.ca_file = Puppet.settings[:localcacert]
    client
  end

  def get_pe_master_group_id
    net = https_client
    res = net.get('/classifier-api/v1/groups')

    unless res.code == '200'
      raise "Failed to fetch groups: HTTP #{res.code} - #{res.body}"
    end

    groups = JSON.parse(res.body)
    pe_master_group = groups.find { |group| group['name'] == 'PE Master' }

    raise 'Could not find PE Master group' unless pe_master_group
    pe_master_group['id']
  rescue JSON::ParserError => e
    raise "Invalid JSON response from server: #{e.message}"
  rescue StandardError => e
    raise "Error fetching PE Master group ID: #{e.message}"
  end

  def get_current_rules(group_id)
    net = https_client
    url = "/classifier-api/v1/groups/#{group_id}/rules"
    req = Net::HTTP::Get.new(url)
    res = net.request(req)

    unless res.code == '200'
      raise "Failed to fetch rules: HTTP #{res.code} - #{res.body}"
    end

    JSON.parse(res.body)['rule']
  rescue JSON::ParserError => e
    raise "Invalid JSON response from server: #{e.message}"
  rescue StandardError => e
    raise "Error fetching rules: #{e.message}"
  end

  def check_rules_updated(rules)
    # If not an array, return false
    return false unless rules.is_a?(Array)

    # Check if this is an 'and' rule with at least 2 elements
    if rules[0] == 'and' && rules.length > 1
      # Check if the first element is an 'or' rule for pe_compiler and pe_compiler_legacy
      if rules[1].is_a?(Array) && rules[1][0] == 'or'
        # Look for the pe_compiler and pe_compiler_legacy rules
        pe_compiler_found = false
        pe_compiler_legacy_found = false

        rules[1][1..-1].each do |rule|
          if rule.is_a?(Array) && 
             rule[0] == '=' && 
             rule[1].is_a?(Array) && 
             rule[1] == ['trusted', 'extensions', 'pp_auth_role']
            
            pe_compiler_found = true if rule[2] == 'pe_compiler'
            pe_compiler_legacy_found = true if rule[2] == 'pe_compiler_legacy'
          end
        end

        return pe_compiler_found && pe_compiler_legacy_found
      end
    end

    # Check if the rule is already using a regex match
    if rules[0] == '~' && 
       rules[1].is_a?(Array) && 
       rules[1] == ['trusted', 'extensions', 'pp_auth_role'] && 
       rules[2] == '^pe_compiler.*$'
      return true
    end

    false
  end

  def execute!
    begin
      group_id = get_pe_master_group_id
      current_rules = get_current_rules(group_id)
      
      is_updated = check_rules_updated(current_rules)
      
      result = {
        'updated' => is_updated,
        'message' => is_updated ? 
          'PE Master rules have already been updated with pe_compiler_legacy support' : 
          'PE Master rules need to be updated to support pe_compiler_legacy'
      }
      
      puts result.to_json
    rescue StandardError => e
      puts({ 'error' => e.message, 'updated' => false }.to_json)
      exit 1
    end
  end
end

# Run the task unless an environment flag has been set
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = CheckPeMasterRules.new(JSON.parse(STDIN.read))
  task.execute!
end 