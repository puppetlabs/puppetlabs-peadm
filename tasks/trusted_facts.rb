#!/opt/puppetlabs/puppet/bin/ruby

require 'openssl'
require 'puppet'
require 'puppet/ssl/oids'
require 'json'

Puppet.initialize_settings
ssldir = Puppet.settings[:ssldir]
certname = Puppet.settings[:certname]

oids = Puppet::SSL::Oids::PUPPET_OIDS.reduce({}) do |memo,oid|
  memo.merge(oid[0] => oid[1])
end

raw = File.read("#{ssldir}/certs/#{certname}.pem")

cert = OpenSSL::X509::Certificate.new(raw)

extensions = cert.extensions.reduce({}) do |memo,ext|
  case oids[ext.oid]
  when nil
    memo.merge(ext.oid => ext.value[2..-1])
  else
    memo.merge(ext.oid => ext.value[2..-1],
               oids[ext.oid] => ext.value[2..-1])
  end
end

result = {'extensions' => extensions}

puts result.to_json
