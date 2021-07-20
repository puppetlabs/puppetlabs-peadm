#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'uri'
require 'net/http'
require 'puppet'

# GetPEAdmConfig task class
class GetPEAdmConfig
  def initialize(params); end

  def execute!
    puts config.to_json
  end

  def config
    # Compute values
    primary = groups.pinned('PE Master')
    replica = groups.pinned('PE HA Replica')
    server_a = server('puppet/server', 'A')
    server_b = server('puppet/server', 'B')
    primary_letter = primary.eql?(server_a) ? 'A' : 'B'
    replica_letter = primary_letter.eql?('A') ? 'B' : 'A'
    postgresql = {
      'A' => server('puppet/puppetdb-database', 'A'),
      'B' => server('puppet/puppetdb-database', 'B'),
    }

    # Build and return the task output
    {
      'params' => {
        'primary_host' => primary,
        'replica_host' => replica,
        'primary_postgresql_host' => postgresql[primary_letter],
        'replica_postgresql_host' => postgresql[replica_letter],
        'compilers' => compilers,
        'compiler_pool_address' => groups.dig('PE Master', 'config_data', 'pe_repo', 'compile_master_pool_address'),
        'internal_compiler_a_pool_address' => groups.dig('PE Compiler Group A', 'classes', 'puppet_enterprise::profile::master', 'puppetdb_host', 1),
        'internal_compiler_b_pool_address' => groups.dig('PE Compiler Group B', 'classes', 'puppet_enterprise::profile::master', 'puppetdb_host', 1),
      },
      'role-letter' => {
        'server' => {
          'A' => server_a,
          'B' => server_b,
        },
        'postgresql' => {
          'A' => postgresql['A'],
          'B' => postgresql['B'],
        },
      },
    }
  end

  # Returns a GetPEAdmConfig::NodeGroups object created from the /groups object
  # returned by the classifier
  def groups
    @groups ||= begin
                  net = https(4433)
                  res = net.get('/classifier-api/v1/groups')
                  NodeGroup.new(JSON.parse(res.body))
                end
  end

  # Returns a list of compiler certnames, based on a PuppetDB query
  def compilers
    query = 'inventory[certname] { trusted.extensions.pp_auth_role = "pe_compiler" }'
    pdb_query(query).map { |n| n['certname'] }
  end

  def server(role, letter)
    query = 'inventory[certname] { '\
            '  trusted.extensions."1.3.6.1.4.1.34380.1.1.9812" = "' + role + '" and ' \
            '  trusted.extensions."1.3.6.1.4.1.34380.1.1.9813" = "' + letter + '"}'

    server = pdb_query(query).map { |n| n['certname'] }
    raise "More than one #{letter} #{role} server found!" unless server.size <= 1
    server.first
  end

  def https(port)
    https = Net::HTTP.new('localhost', port)
    https.use_ssl = true
    https.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
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
      if group.nil?
        nil
      elsif args.empty?
        group
      else
        group.dig(*args)
      end
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