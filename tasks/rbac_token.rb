#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'net/https'
require 'json'
require 'fileutils'
require 'puppet'

# Class to request an RBAC token and write it to disk.
class RbacToken
  # Raised for responses we treat as not worth retrying (a judgement call; see
  # PERMANENT_STATUS_CODES and permanent_failure?). Reported to Bolt under AUTH_FAILURE_KIND so plans
  # that retry this task around rbac-service warm-up windows can fail fast.
  class AuthFailure < RuntimeError; end

  # Matched by string literal in plans/restore.pp and plans/subplans/install.pp
  # (Puppet can't import this constant) -- keep them in sync.
  AUTH_FAILURE_KIND = 'peadm/rbac-auth-failure'

  # HTTP 400 (malformed request) and 401 (bad credentials) are treated as
  # permanent: in normal operation retrying can't fix them. This is a judgement
  # call, not a verified guarantee: PE-46689 saw "User admin failed to login"
  # during warm-up without recording the HTTP status. Everything else -- 5xx
  # from rbac-service warm-up (PE-46689, PE-44867), 403/404/408/429, connection
  # errors -- stays retryable, because we can't rule out that those are
  # transient (e.g. during warm-up); see also SERVER_ERROR_KIND_SUFFIX below.
  # Strings, not integers: Net::HTTPResponse#code returns a String.
  PERMANENT_STATUS_CODES = ['400', '401'].freeze

  # Even for those statuses, a body that rbac-service itself labels a server
  # error is a failure on its side (warm-up, a backing service not ready), not
  # a problem with the request, so it stays retryable. The suffix is an
  # assumption about rbac-service's kind naming (e.g. puppetlabs.rbac/server-error),
  # not something verified against the live service.
  SERVER_ERROR_KIND_SUFFIX = 'server-error'

  # Parameters expected:
  #   Hash
  #     String password
  def initialize(params)
    @params = params
  end

  def execute!
    Puppet.initialize_settings

    body = {
      'login'    => 'admin',
      'password' => @params['password'],
      'lifetime' => @params['token_lifetime'],
      'label'    => 'provision-time token',
    }.to_json

    https = Net::HTTP.new(Puppet.settings[:certname], 4433)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]
    request = Net::HTTP::Post.new('/rbac-api/v1/auth/token')
    request['Content-Type'] = 'application/json'
    request.body = body

    response = https.request(request)
    unless response.is_a? Net::HTTPSuccess
      error_class = permanent_failure?(response) ? AuthFailure : RuntimeError
      raise error_class, "Error requesting token (HTTP #{response.code}), #{response.body}"
    end
    token = JSON.parse(response.body)['token']

    FileUtils.mkdir_p('/root/.puppetlabs')
    File.open('/root/.puppetlabs/token', 'w') { |file| file.write(token) }
  end

  # Runs the task, reporting permanent failures as a Bolt _error with a
  # distinguishable kind. Anything else propagates as a generic task error,
  # which the plans treat as retryable.
  def run!
    execute!
  rescue AuthFailure => e
    # The message embeds an external response body, which Net::HTTP returns
    # binary-tagged; invalid UTF-8 would make to_json raise and mask this as a
    # retryable generic error. scrub is a no-op on binary strings, so re-tag
    # as UTF-8 first.
    msg = e.message.dup.force_encoding('UTF-8').scrub
    puts({ '_error' => { 'msg' => msg, 'kind' => AUTH_FAILURE_KIND } }.to_json)
    exit 1
  end

  private

  def permanent_failure?(response)
    PERMANENT_STATUS_CODES.include?(response.code) && !server_error_body?(response.body)
  end

  # Only a JSON object can carry a kind; anything else (unparseable text, null,
  # true/false, numbers, arrays, strings) is not a server-error label, so the
  # status code decides.
  def server_error_body?(body)
    parsed = JSON.parse(body.to_s)
    parsed.is_a?(Hash) && parsed['kind'].to_s.end_with?(SERVER_ERROR_KIND_SUFFIX)
  rescue JSON::ParserError, EncodingError
    false
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  task = RbacToken.new(JSON.parse(STDIN.read))
  task.run!
end
