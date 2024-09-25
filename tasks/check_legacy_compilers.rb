#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'uri'
require 'net/http'
require 'puppet'

# CheckLegacyCompilers task class
class CheckLegacyCompilers
  def initialize(params)
    @nodes = params['legacy_compilers'].split(',') if params['legacy_compilers'].is_a?(String)
  end

  def execute!
    pinned_nodes = []
    @nodes.each do |node|
      node_classification = get_node_classification(node)
      pinned = false
      node_classification['groups'].each do |group|
        if group['name'] == 'PE Master'
          pinned_nodes << node
          pinned = true
        end
      end
      next if pinned
      next unless node_classification.key?('parameters')
      next unless node_classification['parameters'].key?('pe_master')
      if node_classification['parameters']['pe_master']
        pinned_nodes << node
      end
    end

    return unless !pinned_nodes.empty?
    puts 'The following legacy compilers are classified as Puppet primary nodes:'
    puts pinned_nodes.join(', ')
    puts 'To continue with the upgrade, ensure that these compilers are no longer recognized as Puppet primary nodes.'
  end

  def https(port)
    https = Net::HTTP.new('localhost', port)
    https.use_ssl = true
    https.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE
    https
  end

  def get_node_classification(certname)
    pdb = https(4433)
    pdb_request = Net::HTTP::Post.new('/classifier-api/v2/classified/nodes/' + certname)
    pdb_request['Content-Type'] = 'application/json'

    response = JSON.parse(pdb.request(pdb_request).body)

    response
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = CheckLegacyCompilers.new(JSON.parse(STDIN.read))
  task.execute!
end
