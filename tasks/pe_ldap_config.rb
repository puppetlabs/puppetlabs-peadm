#!/opt/puppetlabs/puppet/bin/ruby
# Puppet Task Name: pe_ldap_config
#
# Update the LDAP configuration
#

require 'json'
require 'net/http'
require 'open3'

def main
  params = JSON.parse(STDIN.read)
  data = params['ldap_config']
  pe_main = params['pe_main']

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

  uri = URI("https://#{pe_main}:4433/rbac-api/v1/ds")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  http.ca_file = cafout.strip
  http.cert = OpenSSL::X509::Certificate.new(File.read(certout.strip))
  http.key = OpenSSL::PKey::RSA.new(File.read(keyout.strip))

  req = Net::HTTP::Put.new(uri, 'Content-type' => 'application/json')
  req.body = data.to_json

  resp = http.request(req)

  puts resp.body
  raise "API response code #{resp.code}" unless resp.code == '200'
end

begin
  main
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
