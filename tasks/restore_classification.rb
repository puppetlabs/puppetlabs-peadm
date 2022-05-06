#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: backup_classification
require 'net/https'
require 'uri'
require 'json'
require 'puppet'

# RestoreClassifiation task class
class RestoreClassification
  def initialize(params)
    @classification_file = params['classification_file']
  end

  def execute!
    restore_classification
    puts "Classification restored from #{@classification_file}"
  end

  private

  def https_client
    client = Net::HTTP.new('localhost', '4433')
    client.use_ssl = true
    client.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    client.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    client.verify_mode = OpenSSL::SSL::VERIFY_NONE
    client
  end

  def restore_classification
    classification = https_client
    classification_post = Net::HTTP::Post.new('/classifier-api/v1/import-hierarchy', 'Content-Type' => 'application/json')
    classification_post.body = File.read(@classification_file)
    classification.request(classification_post)
  end
end
# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = RestoreClassification.new(JSON.parse(STDIN.read))
  task.execute!
end
