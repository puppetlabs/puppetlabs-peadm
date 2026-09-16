# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'open3'

# Shared helpers for the peadm ICA promotion tasks: path resolution, puppetserver
# subcommand invocation, and the mTLS HTTP client used to talk to the PE
# primary's CA and classifier services.
module IcaTaskHelper
  PUPPETSERVER_BIN = '/opt/puppetlabs/bin/puppetserver'
  PUPPETSERVER_CONFDIR = '/etc/puppetlabs/puppetserver'
  ICA_PROVISION_SUBCOMMAND = 'ica-provision'
  CA_SERVICE_PORT = 8140
  CLASSIFIER_PORT = 4433
  # The shared classifier group that ICA compilers are pinned into.
  ICA_GROUP_NAME = 'PE ICA Compilers'
  # The classifier's well-known "All Nodes" root group UUID, used as the
  # parent when creating the ICA compilers group.
  ALL_NODES_GROUP_ID = '00000000-0000-4000-8000-000000000000'
  # Both parameters are declared on puppet_enterprise::profile::master, not on
  # the base puppet_enterprise class. Both must be set together: that class's
  # manifest picks a CA-proxy branch over an intermediate-CA branch whenever
  # enable_ca_proxy is left at its default, so setting pe_ca_ica_enabled alone
  # leaves the node silently unpromoted on its next catalog run.
  ICA_GROUP_CLASSES = {
    'puppet_enterprise::profile::master' => {
      'pe_ca_ica_enabled' => true,
      'enable_ca_proxy' => false,
    },
  }.freeze
  # Read-only network calls (listing/finding classifier groups, checking
  # request status) get a short connect budget; a hung primary should fail
  # fast rather than block the calling plan indefinitely.
  HTTP_OPEN_TIMEOUT = 10
  HTTP_READ_TIMEOUT = 30

  module_function

  def bootstrap_cfg_path
    "#{PUPPETSERVER_CONFDIR}/bootstrap.cfg"
  end

  def ca_conf_path
    "#{PUPPETSERVER_CONFDIR}/conf.d/ca.conf"
  end

  # An uncommented line in bootstrap.cfg naming the given trapperkeeper
  # service. A commented-out line is not evidence either way.
  def active_service_line?(line, service_name)
    !line.strip.start_with?('#') && line.include?(service_name)
  end

  # True only when bootstrap.cfg has an *uncommented* intermediate-ca-service
  # entry. A commented-out line is not evidence of promotion.
  def promoted_to_ica?
    return false unless File.exist?(bootstrap_cfg_path)
    File.readlines(bootstrap_cfg_path).any? { |l| active_service_line?(l, 'intermediate-ca-service') }
  end

  # Runs the puppetserver ICA provisioning subcommand. All ICA cryptography
  # and CSR/CRL construction happens inside the subcommand; this only shells
  # out and captures its result.
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
    https.open_timeout = HTTP_OPEN_TIMEOUT
    https.read_timeout = HTTP_READ_TIMEOUT
    https
  end

  # Pins this compiler into the shared ICA-compilers classifier group,
  # creating the group if it does not yet exist. If the group already exists,
  # its classes are reconciled to ICA_GROUP_CLASSES first: an older or
  # manually edited group could otherwise carry only one of the two required
  # flags and silently leave every compiler pinned to it unpromoted. Pinning
  # an already-pinned node is a no-op on PE's side.
  def pin_to_ica_group!(https, certname)
    existing = find_ica_group(https)
    group_id = existing && existing['id']

    if group_id
      reconcile_ica_group_classes!(https, group_id, existing['classes'])
    else
      group_id = create_ica_group!(https)
    end

    res = https.request(pin_request(group_id, certname))
    return if res.code == '204'
    raise "Failed to pin #{certname} to classifier group #{group_id}: HTTP #{res.code} - #{res.body}"
  end

  def fetch_classifier_groups(https)
    res = https.get('/classifier-api/v1/groups')
    raise "Failed to fetch classifier groups: HTTP #{res.code} - #{res.body}" unless res.code == '200'
    JSON.parse(res.body)
  end

  def find_ica_group(https)
    fetch_classifier_groups(https).find { |g| g['name'] == ICA_GROUP_NAME }
  end

  def find_ica_group_id(https)
    group = find_ica_group(https)
    group && group['id']
  end

  def reconcile_ica_group_classes!(https, group_id, current_classes)
    return if current_classes == ICA_GROUP_CLASSES

    req = Net::HTTP::Post.new("/classifier-api/v1/groups/#{group_id}")
    req['Content-Type'] = 'application/json'
    req.body = { 'classes' => ICA_GROUP_CLASSES }.to_json
    res = https.request(req)
    return if ['200', '201', '204'].include?(res.code)
    raise "Failed to reconcile classifier group #{group_id}'s classes to the required ICA parameters: HTTP #{res.code} - #{res.body}"
  end

  def create_ica_group!(https)
    req = Net::HTTP::Post.new('/classifier-api/v1/groups')
    req['Content-Type'] = 'application/json'
    req.body = {
      'name' => ICA_GROUP_NAME,
      'parent' => ALL_NODES_GROUP_ID,
      'classes' => ICA_GROUP_CLASSES,
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

  # Every task in this pair reports failure the same way: a single-line JSON
  # object on stdout with an `_error` key, never a raw backtrace, so Bolt's
  # caller always gets a machine-readable result.
  def emit_error!(msg, kind)
    STDOUT.puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
  end
end
