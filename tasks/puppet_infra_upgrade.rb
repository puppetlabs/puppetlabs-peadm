#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'uri'
require 'net/https'
require 'json'
require 'open3'
require 'timeout'
require 'etc'
require 'puppet'

# Class to run and execute the `puppet infra upgrade` command as a task.
class PuppetInfraUpgrade
  def initialize(params)
    @type       = params['type']
    @targets    = params['targets']
    @timeout    = params['wait_until_connected_timeout']
    @token_file = params['token_file']
  end

  def execute!
    exit 0 if @targets.empty?
    token_file = @token_file || File.join(Etc.getpwuid.dir, '.puppetlabs', 'token')

    cmd = ['/opt/puppetlabs/bin/puppet-infrastructure', '--color', 'false', '--render-as', 'json', 'upgrade']
    cmd << '--token-file' << token_file unless @token_file.nil?
    cmd << @type << @targets.join(',')

    wait_until_connected(nodes: @targets, token_file: token_file, timeout: @timeout)

    stdouterr, status = Open3.capture2e(*cmd)
    STDOUT.puts stdouterr

    # Exit code 11 indicates PuppetDB sync in progress, just not yet
    # finished. We consider that success.
    if [0, 11].include?(status.exitstatus)
      nil
    else
      exit status.exitstatus
    end
  end

  def request_object(nodes:, token_file:)
    token = File.read(token_file)
    body = {
      'nodes' => nodes,
    }.to_json

    request = Net::HTTP::Post.new('/orchestrator/v1/inventory')
    request['Content-Type'] = 'application/json'
    request['X-Authentication'] = token.chomp
    request.body = body

    request
  end

  def https_object
    https = Net::HTTP.new(Puppet.settings[:certname], 8143)
    https.use_ssl = true
    https.cert = OpenSSL::X509::Certificate.new(File.read(Puppet.settings[:hostcert]))
    https.key = OpenSSL::PKey::RSA.new(File.read(Puppet.settings[:hostprivkey]))
    https.verify_mode = OpenSSL::SSL::VERIFY_PEER
    https.ca_file = Puppet.settings[:localcacert]

    https
  end

  def wait_until_connected(nodes:, token_file:, timeout: 120)
    https = https_object
    request = request_object(nodes: nodes, token_file: token_file)
    inventory = {}
    Timeout.timeout(timeout) do
      loop do
        response = https.request(request)
        unless response.is_a? Net::HTTPSuccess
          body = JSON.parse(response.body)
          raise "Unexpected result from orchestrator: #{response.code}#{body.kind}\n#{body.msg}"
        end
        inventory = JSON.parse(response.body)
        break if inventory['items'].all? { |item| item['connected'] }
        sleep(1)
      end
    end
  rescue Timeout::Error
    raise 'Timed out waiting for nodes to be connected to orchestrator: ' +
          inventory['items'].reject { |item| item['connected'] }
                            .map { |item| item['name'] }
                            .to_s
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  Puppet.initialize_settings
  upgrade = PuppetInfraUpgrade.new(JSON.parse(STDIN.read))
  upgrade.execute!
end
