#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'uri'
require 'net/http'
require 'puppet'

# GetPEAdmConfig task class
class GetPEAdmConfig
  def initialize(params); end

  # Returns a GetPEAdmConfig::NodeGroups object created from the /groups object
  # returned by the classifier
  def groups
    return @groups unless @groups.nil?

    console_services = https(4433)
    response = console_services.get('/classifier-api/v1/groups')

    groups = JSON.parse(response.body)
    @groups = NodeGroup.new(groups)
  end

  # Returns a list of compiler certnames, based on a PuppetDB query
  def compilers
    query = 'inventory[certname] { trusted.extensions.pp_auth_role = "pe_compiler" }'
    pdb_query(query).map { |n| n['certname'] }
  end

  def server(letter)
    query = 'inventory[certname] { '\
            '  trusted.extensions."1.3.6.1.4.1.34380.1.1.9812" = "puppet/server" and ' \
            '  trusted.extensions."1.3.6.1.4.1.34380.1.1.9813" = "' + letter + '"}'

    server = pdb_query(query).map { |n| n['certname'] }
    raise "More than one #{letter} server found!" unless server.size <= 1
    server.first
  end

  def postgresql_server(letter)
    query = 'inventory[certname] { '\
            '  trusted.extensions."1.3.6.1.4.1.34380.1.1.9812" = "puppet/puppetdb-database" and ' \
            '  trusted.extensions."1.3.6.1.4.1.34380.1.1.9813" = "' + letter + '"}'

    server = pdb_query(query).map { |n| n['certname'] }
    raise "More than one #{letter} postgresql server found!" unless server.size <= 1
    server.first
  end

  def config
    server_conf = {
      'primary_host' => groups.pinned('PE Master'),
      'replica_host' => groups.pinned('PE HA Replica'),
      'server_a_host' => server('A'),
      'server_b_host' => server('B'),
    }

    primary_letter = server_conf['primary_host'] == server_conf['server_a_host'] ? 'A' : 'B'
    replica_letter = primary_letter == 'A' ? 'B' : 'A'

    remaining_conf = {
      'primary_postgresql_host' => postgresql_server(primary_letter),
      'replica_postgresql_host' => postgresql_server(replica_letter),
      'postgresql_a_host' => groups.dig('PE Primary A', 'config_data', 'puppet_enterprise::profile::puppetdb', 'database_host'),
      'postgresql_b_host' => groups.dig('PE Primary B', 'config_data', 'puppet_enterprise::profile::puppetdb', 'database_host'),
      'compilers' => compilers,
      'compiler_pool_address' => groups.dig('PE Master', 'config_data', 'pe_repo', 'compile_master_pool_address'),
      'internal_compiler_a_pool_address' => groups.dig('PE Compiler Group A', 'classes', 'puppet_enterprise::profile::master', 'puppetdb_host')[1],
      'internal_compiler_b_pool_address' => groups.dig('PE Compiler Group B', 'classes', 'puppet_enterprise::profile::master', 'puppetdb_host')[1],
    }

    server_conf.merge(remaining_conf)
  end

  def execute!
    puts config.to_json
  end

  def https(port)
    https = Net::HTTP.new('localhost', port)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE
    https
  end

  def pdb_query(query)
    pdb = https(8081)
    pdb_request = Net::HTTP::Get.new('/pdb/query/v4')
    pdb_request.set_form_data({ 'query' => query })
    JSON.parse(pdb.request(pdb_request).body)
  end

  # Utility class to aid in retrieving useful information from the node group
  # data
  class NodeGroup
    attr_reader :data

    def initialize(data)
      @data = data
    end

    # Aids in digging into node groups by name, rather than UUID
    def dig(name, *args)
      group = @data.find { |obj| obj['name'] == name }
      return group if args.empty?
      group.dig(*args)
    end

    # Return the node pinned to the named group
    # If there is more than one node, error
    def pinned(name)
      rule = dig(name, 'rule')
      return nil if rule.nil?
      raise "#{name} rule incompatible with pinning" unless rule.first == 'or'
      pinned = rule.drop(1)
                   .select { |r| r[0] == '=' && r[1] == 'name' }
                   .map { |r| r[2] }
      raise "#{name} contains more than one server!" unless pinned.size <= 1
      pinned.first
    end
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = GetPEAdmConfig.new(JSON.parse(STDIN.read))
  task.execute!
end
