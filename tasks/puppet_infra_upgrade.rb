#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'uri'
require 'net/https'
require 'json'
require 'open3'
require 'timeout'

def main
  params     = JSON.parse(STDIN.read)
  type       = params['type']
  targets    = params['targets']
  timeout    = params['wait_until_connected_timeout']
  token_file = params['token_file'] || '/root/.puppetlabs/token'

  exit 0 if targets.empty?

  cmd = ['/opt/puppetlabs/bin/puppet-infrastructure', '--render-as', 'json', 'upgrade']
  cmd << '--token-file' << token_file unless params['token_file'].nil?
  cmd << type << targets.join(',')

  wait_until_connected(nodes: targets, token_file: token_file, timeout: timeout)

  stdouterr, status = Open3.capture2e(*cmd)
  puts stdouterr
  if status.success?
    exit 0
  else
    exit 1
  end
end

def inventory_uri
  @inventory_uri ||= URI.parse('https://localhost:8143/orchestrator/v1/inventory')
end

def request_object(nodes:, token_file:)
  token = File.read('/root/.puppetlabs/token')
  body = {
    'nodes' => nodes,
  }.to_json

  request = Net::HTTP::Post.new(inventory_uri.request_uri)
  request['Content-Type'] = 'application/json'
  request['X-Authentication'] = token
  request.body = body

  request
end

def http_object
  http = Net::HTTP.new(inventory_uri.host, inventory_uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  http
end

def wait_until_connected(nodes:, token_file:, timeout: 120)
  http = http_object
  request = request_object(nodes: nodes, token_file: token_file)
  inventory = {}
  Timeout::timeout(timeout) do
    loop do
      response = http.request(request)
      raise unless response.is_a? Net::HTTPSuccess
      inventory = JSON.parse(response.body)
      break if inventory['items'].all? { |item| item['connected'] }
      sleep(1)
    end
  end
rescue Timeout::Error
  raise "Timed out waiting for nodes to be connected to orchestrator: " +
        inventory['items'].select { |item| !item['connected'] }
                          .map { |item| item['name'] }
                          .to_s
end

main
