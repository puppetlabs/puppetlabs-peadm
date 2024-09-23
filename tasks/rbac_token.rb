#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

#
# rubocop:disable Style/GlobalVars
require 'net/https'
require 'json'
require 'fileutils'
require 'puppet'

# Parameters expected:
#   Hash
#     String password
$params = JSON.parse(STDIN.read)

Puppet.initialize_settings

body = {
  'login'    => 'admin',
  'password' => $params['password'],
  'lifetime' => $params['token_lifetime'],
  'label'    => 'provision-time token',
}.to_json

https = Net::HTTP.new(Puppet.settings[:certname], 4433)
https.use_ssl = true
https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
https.verify_mode = OpenSSL::SSL::VERIFY_PEER
https.ca_file = Puppet.settings[:localcacert]
request = Net::HTTP::Post.new('/rbac-api/v1/auth/token')
request['Content-Type'] = 'application/json'
request.body = body

response = https.request(request)
raise "Error requesting token, #{response.body}" unless response.is_a? Net::HTTPSuccess
token = JSON.parse(response.body)['token']

FileUtils.mkdir_p('/root/.puppetlabs')
File.open('/root/.puppetlabs/token', 'w') { |file| file.write(token) }
