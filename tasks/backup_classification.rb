#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: backup_classification
require 'net/https'
require 'uri'
require 'json'
require 'puppet'

# BackupClassiciation task class
class BackupClassification
  def initialize(params)
    @params = params
  end

  def execute!
    File.write("#{@params['directory']}/classification_backup.json", return_classification)
    puts "Classification written to #{@params['directory']}/classification_backup.json"
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

  def return_classification
    classification = https_client
    classification_request = Net::HTTP::Get.new('/classifier-api/v1/groups')

    classification.request(classification_request).body
  end
end
# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  task = BackupClassification.new(JSON.parse(STDIN.read))
  task.execute!
end
