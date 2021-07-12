#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'openssl'
require 'puppet'
require 'puppet/ssl/oids'
require 'json'

# Implementation class for task
class CertData
  def initialize(params)
    @params = params
  end

  def execute!
    Puppet.settings.use(:agent, :server, :master, :main)
    certpath = Puppet.settings[:hostcert]
    result = if File.exist?(certpath)
               cert = x509_certificate_from_path(certpath)
               {
                 'certificate-exists' => true,
                 'certname'      => certname_from_x509_certificate(cert),
                 'extensions'    => extensions_from_x509_certificate(cert),
                 'dns-alt-names' => alt_names_from_x509_certificate(cert),
               }
             else
               {
                 'certificate-exists' => false,
                 'certname'      => Puppet.settings[:certname],
                 'extensions'    => extensions_from_csr_attributes_path(Puppet.settings[:csr_attributes]),
                 'dns-alt-names' => Puppet.settings[:dns_alt_names].to_s.split(','),
               }
             end

    # Put the result to stdout
    puts result.to_json
  end

  def x509_certificate_from_path(path)
    return nil unless File.exist?(path)
    raw = File.read(path)
    OpenSSL::X509::Certificate.new(raw)
  end

  def certname_from_x509_certificate(cert)
    cert.subject.to_a.find { |item| item[0] == 'CN' }
        .slice(1)
  end

  def extensions_from_x509_certificate(cert)
    friendly_names = Puppet::SSL::Oids::PUPPET_OIDS.reduce({}) do |memo, oid|
      memo.merge(oid[0] => oid[1])
    end

    cert.extensions.reduce({}) do |memo, ext|
      next memo unless ext.oid.start_with?('1.3.6.1.4.1.34380.1') # ppCertExt
      case friendly_names[ext.oid]
      when nil
        memo.merge({ ext.oid => ext.value[2..-1] })
      else
        memo.merge({ ext.oid => ext.value[2..-1], friendly_names[ext.oid] => ext.value[2..-1] })
      end
    end
  end

  def alt_names_from_x509_certificate(cert)
    # Make sure this works for certs with or without subjectAltName extensions
    cert.extensions.select { |ext| ext.oid == 'subjectAltName' }
        .map { |ext| ext.value.split(', ') }
        .flatten
        .map { |str| str.slice(%r{^(DNS:)(.*)}, 2) }
  end

  def extensions_from_csr_attributes_path(path)
    return {} unless File.exist?(path)

    data = YAML.safe_load(File.read(path))
    extension_requests = data['extension_requests']

    oids = Puppet::SSL::Oids::PUPPET_OIDS.reduce({}) do |memo, oid|
      memo.merge(oid[1] => oid[0])
    end

    extension_requests.reduce({}) do |memo, (request, value)|
      case oids[request]
      when nil
        memo.merge({ request => value })
      else
        memo.merge({ request => value, oids[request] => value })
      end
    end
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  cert_data = CertData.new(JSON.parse(STDIN.read))
  cert_data.execute!
end
