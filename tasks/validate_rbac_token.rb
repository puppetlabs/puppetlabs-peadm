#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'uri'
require 'net/https'
require 'json'
require 'etc'
require 'puppet'

# Class to check an rbac token is valid
class ValidateRbacToken
  def initialize(params)
    @token_file = params['token_file']
  end

  def execute!
    token_file = @token_file || File.join(Etc.getpwuid.dir, '.puppetlabs', 'token')

    uri = URI("https://#{Puppet.settings[:certname]}:4433/rbac-api/v2/auth/token/authenticate")
    https = https_object(uri: uri)
    request = request_object(token_file: token_file)

    resp = https.request(request)

    if resp.code == '200'
      puts 'RBAC token is valid'
      exit 0
    else
      body = JSON.parse(resp.body)
      case resp.code
      when '401', '403'
        puts "#{resp.code} #{body['kind']}: " \
             "Check your API token at #{token_file}.\n" \
             "Please refresh your token or provide an alternate file.\n" \
             "See https://www.puppet.com/docs/pe/latest/rbac_token_auth_intro for more details.\n"
      else
        puts "Error validating token: #{resp.code} #{body['kind']}"
        puts body['msg']
      end

      exit 1
    end
  end

  def request_object(token_file:)
    token = File.read(token_file)
    body = {
      'token' => token.chomp,
      'update_last_activity?' => false,
    }.to_json

    request = Net::HTTP::Post.new('/rbac-api/v2/auth/token/authenticate')
    request['Content-Type'] = 'application/json'
    request.body = body

    request
  end

  def https_object(uri:)
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]

    https
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  validate = ValidateRbacToken.new(JSON.parse(STDIN.read))
  validate.execute!
end
