#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'openssl'
require 'puppet'
require 'puppet/ssl/oids'
require 'json'

Puppet.initialize_settings
ssldir = Puppet.settings[:ssldir]
certname = Puppet.settings[:certname]

oids = Puppet::SSL::Oids::PUPPET_OIDS.reduce({}) do |memo, oid|
  memo.merge(oid[0] => oid[1])
end

raw = File.read("#{ssldir}/certs/#{certname}.pem")

cert = OpenSSL::X509::Certificate.new(raw)

extensions = cert.extensions.reduce({}) do |memo, ext|
  next memo unless ext.oid.start_with?('1.3.6.1.4.1.34380.1') # ppCertExt
  case oids[ext.oid]
  when nil
    memo.merge(ext.oid => ext.value[2..-1])
  else
    memo.merge(ext.oid => ext.value[2..-1],
               oids[ext.oid] => ext.value[2..-1])
  end
end

alt_names = cert.extensions.select { |ext| ext.oid == 'subjectAltName' }.map { |ext|
  ext.value.split(', ').map { |str| str[4..-1] }
}.first

result = {
  'certname'      => certname,
  'dns-alt-names' => alt_names,
  'extensions'    => extensions,
}

puts result.to_json
