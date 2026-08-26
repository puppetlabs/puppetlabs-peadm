# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'open3'

# Shared helpers for the peadm ICA promotion tasks (submit_ica_csr,
# install_ica_cert): path resolution, puppetserver subcommand invocation, and
# the mTLS HTTP client used to talk to the PE primary's CA and classifier
# services. See ticket PE-44791.
module IcaTaskHelper
  PUPPETSERVER_BIN = '/opt/puppetlabs/bin/puppetserver'
  PUPPETSERVER_CONFDIR = '/etc/puppetlabs/puppetserver'
  # NOTE: subcommand verb not yet confirmed against the merged ticket 7.1
  # (PE-44789) implementation — update this constant if it differs.
  ICA_PROVISION_SUBCOMMAND = 'ica-provision'
  CA_SERVICE_PORT = 8140
  CLASSIFIER_PORT = 4433
  # NOTE: group name/parent not specified anywhere in PE-44791/44789/44794 or
  # spec.md as of 2026-08 — confirm with the ticket 5.5 classification owner.
  ICA_GROUP_NAME = 'PE ICA Compilers'
  # The classifier's well-known "All Nodes" root group UUID, used as the
  # parent when creating the ICA compilers group.
  ALL_NODES_GROUP_ID = '00000000-0000-4000-8000-000000000000'

  module_function

  def bootstrap_cfg_path
    "#{PUPPETSERVER_CONFDIR}/bootstrap.cfg"
  end

  def ca_conf_path
    "#{PUPPETSERVER_CONFDIR}/conf.d/ca.conf"
  end

  # True only when bootstrap.cfg has an *uncommented* intermediate-ca-service
  # entry. A commented-out line is not evidence of promotion.
  def promoted_to_ica?
    return false unless File.exist?(bootstrap_cfg_path)
    File.readlines(bootstrap_cfg_path).any? { |l| !l.strip.start_with?('#') && l.include?('intermediate-ca-service') }
  end

  # Runs the puppetserver ICA provisioning subcommand (ticket 7.1 / PE-44789).
  # All ICA cryptography and CSR/CRL construction happens inside the
  # subcommand; this only shells out and captures its result.
  def run_ica_provision
    Open3.capture3(PUPPETSERVER_BIN, ICA_PROVISION_SUBCOMMAND)
  end

  # Builds an mTLS-authenticated Net::HTTP client to the given host, using
  # this compiler's Puppet agent certificate. peadm never uses RBAC tokens:
  # every existing classifier/PuppetDB-calling task authenticates this way.
  def primary_https_client(hostname, port = CA_SERVICE_PORT)
    https = Net::HTTP.new(hostname, port)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]
    https
  end

  # Pins this compiler into the shared ICA-compilers classifier group,
  # creating the group (with pe_ca_ica_enabled => true) if it does not yet
  # exist. Idempotent: pinning an already-pinned node is a no-op on PE's side.
  def pin_to_ica_group!(https, certname)
    group_id = find_ica_group_id(https) || create_ica_group!(https)

    res = https.request(pin_request(group_id, certname))
    return if res.code == '204'
    raise "Failed to pin #{certname} to classifier group #{group_id}: HTTP #{res.code} - #{res.body}"
  end

  def find_ica_group_id(https)
    res = https.get('/classifier-api/v1/groups')
    raise "Failed to fetch classifier groups: HTTP #{res.code} - #{res.body}" unless res.code == '200'

    group = JSON.parse(res.body).find { |g| g['name'] == ICA_GROUP_NAME }
    group && group['id']
  end

  def create_ica_group!(https)
    req = Net::HTTP::Post.new('/classifier-api/v1/groups')
    req['Content-Type'] = 'application/json'
    req.body = {
      'name' => ICA_GROUP_NAME,
      'parent' => ALL_NODES_GROUP_ID,
      'classes' => { 'puppet_enterprise' => { 'pe_ca_ica_enabled' => true } },
    }.to_json

    res = https.request(req)
    raise "Failed to create classifier group #{ICA_GROUP_NAME}: HTTP #{res.code} - #{res.body}" unless res.code.to_i == 303

    location = res['location']
    raise "Classifier group creation returned 303 but no Location header for #{ICA_GROUP_NAME}" if location.nil? || location.empty?
    location.split('/')[-1]
  end

  def pin_request(group_id, certname)
    req = Net::HTTP::Post.new("/classifier-api/v1/groups/#{group_id}/pin")
    req['Content-Type'] = 'application/json'
    req.body = { 'nodes' => [certname] }.to_json
    req
  end
end
