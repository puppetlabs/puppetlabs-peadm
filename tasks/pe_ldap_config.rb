#!/opt/puppetlabs/puppet/bin/ruby
# Puppet Task Name: pe_ldap_config
#
# Update the LDAP configuration
#

require 'json'
require 'net/http'
require 'open3'

# Class which updates the LDAP configuration via the RBAC API: the legacy
# directory-settings endpoint for PE versions before 2023.8.0, and the
# newer ldap/create command endpoint from 2023.8.0 onward.
class PeLdapConfig
  def initialize(params)
    @data = params['ldap_config']
    @pe_main = params['pe_main']
    @pe_version = params['pe_version']
  end

  def execute!
    caf = ['/opt/puppetlabs/bin/puppet', 'config', 'print', 'localcacert']
    cafout, cafstatus = Open3.capture2(*caf)
    unless cafstatus.success?
      raise 'Could not get the CA file path.'
    end

    cert = ['/opt/puppetlabs/bin/puppet', 'config', 'print', 'hostcert']
    certout, certstatus = Open3.capture2(*cert)
    unless certstatus.success?
      raise 'Could not get the Cert file path.'
    end

    key = ['/opt/puppetlabs/bin/puppet', 'config', 'print', 'hostprivkey']
    keyout, keystatus = Open3.capture2(*key)
    unless keystatus.success?
      raise 'Could not get the Key file path.'
    end

    if Gem::Version.new(@pe_version) < Gem::Version.new('2023.8.0')
      ldap_path = URI('rbac-api/v1/ds')
      uri = URI("https://#{@pe_main}:4433/#{ldap_path}")
      req = Net::HTTP::Put.new(uri, 'Content-type' => 'application/json')
    else
      ldap_path = URI('rbac-api/v1/command/ldap/create')
      uri = URI("https://#{@pe_main}:4433/#{ldap_path}")
      req = Net::HTTP::Post.new(uri, 'Content-type' => 'application/json')
    end

    https = Net::HTTP.new(@pe_main, '4433')
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = cafout.strip
    https.cert = OpenSSL::X509::Certificate.new(File.read(certout.strip))
    https.key = OpenSSL::PKey::RSA.new(File.read(keyout.strip))

    req.body = @data.to_json

    resp = https.request(req)

    # Don't print the response body: Bolt logs the task's output, the legacy
    # ds endpoint returns the settings it saved, bind password included, and
    # RBAC error bodies can echo the submitted request (PE-47523).
    raise "API response code #{resp.code}#{error_kind(resp.body)}" unless resp.code == '200'

    puts({ 'status' => resp.code }.to_json)
  end

  # The error kind from an RBAC error body, as " (<kind>)", or '' if the body
  # isn't a JSON object with a plain kind
  def error_kind(body)
    parsed = JSON.parse(body.to_s)
    kind = parsed['kind'] if parsed.is_a?(Hash)
    (kind.is_a?(String) && kind.match?(%r{\A[\w./-]+\z})) ? " (#{kind})" : ''
  rescue JSON::ParserError, EncodingError
    ''
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  begin
    task = PeLdapConfig.new(JSON.parse(STDIN.read))
    task.execute!
  rescue => e
    result = {
      '_error' => {
        'msg'     => e.message,
        'kind'    => 'RuntimeError',
        'details' => e.message,
      }
    }
    puts result.to_json
    exit(1)
  end
end
