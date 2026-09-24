# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'etc'

# Shared helpers for the peadm ICA demotion tasks: path resolution, HOCON
# config edits, and the HTTP/token primitives used to talk to the PE
# primary's CA service.
module IcaTaskHelper
  PUPPETSERVER_CONFDIR = '/etc/puppetlabs/puppetserver'
  CA_SERVICE_PORT = 8140
  DEFAULT_ICA_PASSPHRASE_PATH = '/etc/puppetlabs/puppetserver/ssl/ica_passphrase'
  # Certnames are hostnames, so this matches the standard hostname shape:
  # alphanumerics, dots, hyphens and underscores, starting and ending on an
  # alphanumeric. Every task that interpolates a compiler_fqdn parameter
  # into an HTTP request path must validate it first -- Net::HTTP checks
  # header values for embedded CR/LF but not the request path, so an
  # unvalidated fqdn could otherwise smuggle a second request or extra
  # headers onto an authenticated connection to the CA service.
  VALID_FQDN = %r{\A[a-zA-Z0-9]([a-zA-Z0-9_.-]*[a-zA-Z0-9])?\z}.freeze

  module_function

  def validate_fqdn!(fqdn)
    return if fqdn.match?(VALID_FQDN)
    raise ArgumentError, "invalid compiler_fqdn: #{fqdn.inspect}"
  end

  def bootstrap_cfg_path
    "#{PUPPETSERVER_CONFDIR}/bootstrap.cfg"
  end

  def ca_conf_path
    "#{PUPPETSERVER_CONFDIR}/conf.d/ca.conf"
  end

  # Builds an mTLS-authenticated Net::HTTP client to the given host, using
  # this node's Puppet agent certificate. Every read and certname-allowed
  # route peadm calls authenticates this way alone; the RBAC-only mutation
  # routes (drain, revoke, decommission) additionally require an
  # X-Authentication header built from rbac_token below, since no certname
  # allowance exists for them (see puppet-enterprise-modules' tk_authz.pp).
  def primary_https_client(hostname, port = CA_SERVICE_PORT)
    https = Net::HTTP.new(hostname, port)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]
    https
  end

  # Path to the RBAC token file a caller obtained via `puppet access login`
  # (or peadm::rbac_token), same default `puppet_infra_upgrade` already uses
  # against the orchestrator.
  def default_token_file
    File.join(Etc.getpwuid.dir, '.puppetlabs', 'token')
  end

  def rbac_token(token_file)
    File.read(token_file || default_token_file).chomp
  end

  # Reverts bootstrap.cfg from ICA mode back to CA-proxy mode: removes any
  # uncommented intermediate-ca-service entry and ensures the
  # certificate-authority-disabled-service entry is present. Idempotent -- a
  # compiler already in proxy mode is a no-op. Returns false rather than
  # silently doing nothing when bootstrap.cfg itself is missing, since that
  # is also what a wrong path or a broken puppetserver install looks like,
  # not only an already-reverted compiler -- the caller needs to be able to
  # tell those apart instead of reporting success either way.
  def revert_bootstrap_to_proxy!
    path = bootstrap_cfg_path
    return false unless File.exist?(path)

    lines = File.readlines(path)
    lines.reject! { |l| !l.strip.start_with?('#') && l.include?('intermediate-ca-service') }
    unless lines.any? { |l| !l.strip.start_with?('#') && l.include?('certificate-authority-disabled-service') }
      lines[-1] = "#{lines[-1]}\n" if lines.any? && !lines[-1].end_with?("\n")
      lines << "puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service\n"
    end
    File.write(path, lines.join)
    true
  end

  # Reads a single HOCON setting, or nil if the file or the setting doesn't
  # exist.
  def get_hocon_value(path, setting)
    return nil unless File.exist?(path)
    require 'hocon/config_factory'

    config = Hocon::ConfigFactory.parse_file(path).resolve
    config.has_path?(setting) ? config.get_string(setting) : nil
  end

  # Sets a single HOCON setting in place, preserving comments and formatting
  # via the config *document* API -- the same mechanism pe_hocon_setting's
  # own ruby provider uses, rather than ConfigFactory, which only exposes the
  # resolved value tree and would drop everything else in the file on write.
  def set_hocon_value!(path, setting, value)
    require 'hocon/parser/config_document_factory'
    require 'hocon/config_value_factory'

    File.write(path, '') unless File.exist?(path)
    doc = Hocon::Parser::ConfigDocumentFactory.parse_file(path)
    new_value = Hocon::ConfigValueFactory.from_any_ref(value, nil)
    updated = doc.set_config_value(setting, new_value)
    File.write(path, updated.render)
  end
end
