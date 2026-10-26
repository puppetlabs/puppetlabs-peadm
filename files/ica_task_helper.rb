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
  # Promotion is two classifier stages, each its own group, because the two
  # halves must not take effect together: the settings the ICA provisioning
  # subcommand reads have to be on the compiler before the CSR exists, while
  # the flags that bind IntermediateCAService must not be set until the
  # approved certificate and passphrase are there.
  #
  # PE Intermediate CA (under PE Infrastructure) is stage one. Its only job is
  # profile::compiler_ica_ca's ica_enabled, which makes that class write the
  # ica-* settings into ca.conf while the compiler is still a CA proxy.
  ICA_PARENT_GROUP_NAME = 'PE Intermediate CA'
  ICA_PARENT_GROUP_PARENT_NAME = 'PE Infrastructure'
  ICA_PARENT_GROUP_CLASSES = {
    'puppet_enterprise::profile::compiler_ica_ca' => {
      'ica_enabled' => true,
    },
  }.freeze
  # PE ICA Compilers is stage two, a child of PE Intermediate CA. A node must
  # match every ancestor's rule to belong to a group, so a node can only reach
  # this group by also being pinned to the parent: it inherits ica_enabled from
  # there and cannot bind the service without the stage-one settings.
  #
  # profile::master's two flags must be set together: its manifest picks a
  # CA-proxy branch over an intermediate-CA branch whenever enable_ca_proxy
  # is left at its default, so setting pe_ca_ica_enabled alone leaves the
  # node silently unpromoted on its next catalog run.
  #
  # Writing bootstrap.cfg and restarting the service in response is
  # profile::master's own job on the next Puppet run, not a task's.
  ICA_GROUP_NAME = 'PE ICA Compilers'
  ICA_GROUP_CLASSES = {
    'puppet_enterprise::profile::master' => {
      'pe_ca_ica_enabled' => true,
      'enable_ca_proxy' => false,
    },
  }.freeze
  # The ca.conf settings profile::compiler_ica_ca writes, all of which the ICA
  # provisioning subcommand and IntermediateCAService need to find on disk.
  ICA_CA_CONF_SETTINGS = [
    'ica-passphrase-path',
    'ica-renewal-primary-url',
    'ica-renewal-root-ca-cert-path',
  ].freeze
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
  # this compiler's Puppet agent certificate. The classifier and CA routes the
  # ICA tasks call accept that certificate, so these tasks need no RBAC token.
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

  # Stage one: pins this compiler into PE Intermediate CA, creating the group
  # under PE Infrastructure if it does not yet exist. After a Puppet run on the
  # compiler, its ca.conf carries the settings ica-provision reads.
  def pin_to_ica_parent_group!(https, certname)
    groups = fetch_classifier_groups(https)
    infrastructure = find_group(groups, ICA_PARENT_GROUP_PARENT_NAME)
    unless infrastructure && infrastructure['id']
      raise "Classifier group #{ICA_PARENT_GROUP_PARENT_NAME} not found; cannot create #{ICA_PARENT_GROUP_NAME} under it"
    end

    group_id = ensure_group!(https, groups, ICA_PARENT_GROUP_NAME, infrastructure['id'], ICA_PARENT_GROUP_CLASSES)
    pin!(https, group_id, certname)
  end

  # Stage two: pins this compiler into PE ICA Compilers, a child of
  # PE Intermediate CA. The node has to be pinned to the parent first. A pin
  # to the child alone is accepted by the classifier but never matches, since
  # a node must satisfy every ancestor's rule, so refusing here turns a silent
  # no-op into a clear error.
  def pin_to_ica_group!(https, certname)
    groups = fetch_classifier_groups(https)
    parent = find_group(groups, ICA_PARENT_GROUP_NAME)
    unless parent && parent['id']
      raise "Classifier group #{ICA_PARENT_GROUP_NAME} does not exist: this compiler has not been enabled for ICA provisioning. Run peadm::enable_ica_provisioning first."
    end
    unless pinned_to?(parent, certname)
      raise "#{certname} is not pinned to #{ICA_PARENT_GROUP_NAME}, so it would never match #{ICA_GROUP_NAME}. Run peadm::enable_ica_provisioning first."
    end

    group_id = ensure_group!(https, groups, ICA_GROUP_NAME, parent['id'], ICA_GROUP_CLASSES)
    pin!(https, group_id, certname)
  end

  def fetch_classifier_groups(https)
    res = https.get('/classifier-api/v1/groups')
    raise "Failed to fetch classifier groups: HTTP #{res.code} - #{res.body}" unless res.code == '200'
    JSON.parse(res.body)
  end

  def find_group(groups, name)
    groups.find { |g| g['name'] == name }
  end

  # Whether the group's rule names this node. A pin is stored as an equality
  # on the node's name inside the group's rule.
  def pinned_to?(group, certname)
    Array(group['rule']).flatten.include?(certname)
  end

  # Returns the id of the named group, creating it under parent_id or
  # reconciling its classes as needed. A group that already exists under some
  # other parent is left alone: moving it would change what every node already
  # pinned to it inherits, which is not this task's call to make.
  def ensure_group!(https, groups, name, parent_id, classes)
    existing = find_group(groups, name)
    return create_group!(https, name, parent_id, classes) unless existing && existing['id']

    if existing['parent'] != parent_id
      raise "Classifier group #{name} already exists under a different parent (#{existing['parent']}) than expected (#{parent_id}); " \
            'refusing to re-parent it. Manual intervention required.'
    end

    reconcile_group_classes!(https, name, existing['id'], existing['classes'], classes)
    existing['id']
  end

  # An older or manually edited group could carry only some of its required
  # classes and silently leave every compiler pinned to it in the wrong state.
  def reconcile_group_classes!(https, name, group_id, current_classes, required_classes)
    return if current_classes == required_classes

    req = Net::HTTP::Post.new("/classifier-api/v1/groups/#{group_id}")
    req['Content-Type'] = 'application/json'
    req.body = { 'classes' => required_classes }.to_json
    res = https.request(req)
    return if ['200', '201', '204'].include?(res.code)
    raise "Failed to reconcile classifier group #{name} (#{group_id}) to its required classes: HTTP #{res.code} - #{res.body}"
  end

  def create_group!(https, name, parent_id, classes)
    req = Net::HTTP::Post.new('/classifier-api/v1/groups')
    req['Content-Type'] = 'application/json'
    req.body = { 'name' => name, 'parent' => parent_id, 'classes' => classes }.to_json

    res = https.request(req)
    raise "Failed to create classifier group #{name}: HTTP #{res.code} - #{res.body}" unless res.code.to_i == 303

    location = res['location']
    raise "Classifier group creation returned 303 but no Location header for #{name}" if location.nil? || location.empty?
    location.split('/')[-1]
  end

  def pin!(https, group_id, certname)
    res = https.request(pin_request(group_id, certname))
    return if res.code == '204'
    raise "Failed to pin #{certname} to classifier group #{group_id}: HTTP #{res.code} - #{res.body}"
  end

  def pin_request(group_id, certname)
    req = Net::HTTP::Post.new("/classifier-api/v1/groups/#{group_id}/pin")
    req['Content-Type'] = 'application/json'
    req.body = { 'nodes' => [certname] }.to_json
    req
  end

  # The ICA settings found uncommented in ca.conf, keyed by setting name. A
  # missing ca.conf is an empty result rather than an error: the caller's
  # question is whether the settings are there.
  def ca_conf_ica_settings
    return {} unless File.exist?(ca_conf_path)

    content = File.read(ca_conf_path)
    ICA_CA_CONF_SETTINGS.each_with_object({}) do |key, found|
      match = content.match(%r{^[ \t]*#{Regexp.escape(key)}[ \t]*[:=][ \t]*"([^"\n]*)"})
      found[key] = match[1] if match
    end
  end

  # Stage two binds IntermediateCAService on the next Puppet run, and that
  # service will not initialise without the ca.conf settings or the passphrase
  # the provisioning subcommand creates. Failing here is cheap; discovering it
  # as a pe-puppetserver that does not come back is not.
  def assert_provisioning_ready!
    settings = ca_conf_ica_settings
    missing = ICA_CA_CONF_SETTINGS - settings.keys
    unless missing.empty?
      raise "ca.conf is missing #{missing.join(', ')}. Run peadm::enable_ica_provisioning and a Puppet run on this compiler first: " \
            "pinning it to #{ICA_GROUP_NAME} now would bind IntermediateCAService without them and pe-puppetserver would fail to start."
    end

    passphrase = settings['ica-passphrase-path']
    return if File.exist?(passphrase)
    raise "No ICA passphrase at #{passphrase}. Run peadm::submit_ica_csr first: " \
          "pinning this compiler to #{ICA_GROUP_NAME} without it would leave IntermediateCAService unable to start."
  end

  # Every task in this pair reports failure the same way: a single-line JSON
  # object on stdout with an `_error` key, never a raw backtrace, so Bolt's
  # caller always gets a machine-readable result.
  def emit_error!(msg, kind)
    STDOUT.puts({ '_error' => { 'msg' => msg, 'kind' => kind } }.to_json)
  end
end
