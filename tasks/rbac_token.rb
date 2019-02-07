#!/opt/puppetlabs/puppet/bin/ruby
#
# rubocop:disable Style/GlobalVars
require 'net/https'
require 'uri'
require 'json'
require 'fileutils'

# Parameters expected:
#   Hash
#     String password
$params = JSON.parse(STDIN.read)

uri = URI.parse('https://localhost:4433/rbac-api/v1/auth/token')
body = {
  'login'    => 'admin',
  'password' => $params['password'],
  'lifetime' => '1y',
  'label'    => 'provision-time token',
}.to_json

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
request = Net::HTTP::Post.new(uri.request_uri)
request['Content-Type'] = 'application/json'
request.body = body

response = http.request(request)
raise unless response.is_a? Net::HTTPSuccess
token = JSON.parse(response.body)['token']

FileUtils.mkdir_p('/root/.puppetlabs')
File.open('/root/.puppetlabs/token', 'w') { |file| file.write(token) }
