#!/opt/puppetlabs/puppet/bin/ruby

# Puppet Task Name: backup_classification
require 'net/https'
require 'uri'
require 'json'
require 'puppet'

# CodeSyncStatus task class
class BackupClassification
  def initialize(params)
    @params = params
  end

  def execute!
    File.write(@params['file'],return_classification)
    puts "Classification written to @params['file']"
  end 

  private

  def https_client
    client = Net::HTTP.new('localhost', '8140')
    client.use_ssl = true
    client.cert = @cert ||= OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    client.key = @key ||= OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    client.verify_mode = OpenSSL::SSL::VERIFY_NONE
    client
  end

  def return_classification
    classification = https_client
    classification_request = Net::HTTP::Get.new('/status/v1/services?level=debug')  
    
     JSON.parse(classification.request(classification_request).body))
  end

end