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

    # Check if there is at least 2 elements
    if rules.length > 1
      # Check if the first element is an 'or' rule for pe_compiler and pe_compiler_legacy
      if rules[1].is_a?(Array) && rules[1][0] == 'or'
        # Look for the pe_compiler and pe_compiler_legacy rules
        pe_compiler_found = false
        pe_compiler_legacy_found = false

        rules[1][1..-1].each do |rule|
          next unless rule.is_a?(Array) &&
                      rule[0] == '=' &&
                      rule[1].is_a?(Array) &&
                      rule[1] == ['trusted', 'extensions', 'pp_auth_role']

          pe_compiler_found = true if rule[2] == 'pe_compiler'
          pe_compiler_legacy_found = true if rule[2] == 'pe_compiler_legacy'
        end

        return pe_compiler_found && pe_compiler_legacy_found
      end
    end

    false
  end

  def https_pdb_client(port = 8081)
    client = Net::HTTP.new(Puppet.settings[:certname], port)
    client.use_ssl = true
    client.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    client.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    client.verify_mode = OpenSSL::SSL::VERIFY_PEER
    client.ca_file = Puppet.settings[:localcacert]
    client
  end

  def check_nodes_with_legacy_compiler_oid
    pdb = https_pdb_client
    pdb_request = Net::HTTP::Get.new('/pdb/query/v4')
    pdb_request.set_form_data({
                                'query' => 'inventory[certname,trusted.extensions] {
        trusted.extensions."1.3.6.1.4.1.34380.1.1.9814" is not null
      }'
                              })

    response = pdb.request(pdb_request)

    unless response.code == '200'
      raise "Failed to query PuppetDB: HTTP #{response.code} - #{response.body}"
    end

    nodes = JSON.parse(response.body)

    {
      'nodes_found' => !nodes.empty?,
      'count' => nodes.size,
      'nodes' => nodes.map { |n| n['certname'] }
    }
  rescue JSON::ParserError => e
    raise "Invalid JSON response from PuppetDB: #{e.message}"
  rescue StandardError => e
    raise "Error checking for legacy compiler OID: #{e.message}"
  end

  def execute!
    group_id = get_pe_master_group_id
    current_rules = get_current_rules(group_id)

    rules_updated = check_rules_updated(current_rules)
    legacy_compiler_nodes = check_nodes_with_legacy_compiler_oid

    # Overall status is updated only if rules are updated AND no nodes have legacy compiler OID
    is_updated = rules_updated && !legacy_compiler_nodes['nodes_found']

    message = if !rules_updated
                'PE Master rules need to be updated to support pe_compiler_legacy'
              elsif legacy_compiler_nodes['nodes_found']
                'PE Master rules are updated, but nodes with legacy compiler OID still exist'
              else
                'PE Master rules have been updated with pe_compiler_legacy support and no legacy compiler OIDs found'
              end

    result = {
      'updated' => is_updated,
      'message' => message,
      'legacy_compiler_oid' => legacy_compiler_nodes
    }

    puts result.to_json
  rescue StandardError => e
    puts({ 'error' => e.message, 'updated' => false }.to_json)
    exit 1
  end
end

# Run the task unless an environment flag has been set
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = CheckPeMasterRules.new(JSON.parse(STDIN.read))
  task.execute!
end
