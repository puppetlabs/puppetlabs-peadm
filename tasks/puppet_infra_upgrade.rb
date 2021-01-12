#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'uri'
require 'net/https'
require 'json'
require 'open3'
require 'timeout'
require 'etc'

class PEAdm
  class Task
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

        cmd = ['/opt/puppetlabs/bin/puppet-infrastructure', '--render-as', 'json', 'upgrade']
        cmd << '--token-file' << token_file unless @token_file.nil?
        cmd << @type << @targets.join(',')

        wait_until_connected(nodes: @targets, token_file: token_file, timeout: @timeout)

        stdouterr, status = Open3.capture2e(*cmd)
        STDOUT.puts stdouterr

        # Exit code 11 indicates PuppetDB sync in progress, just not yet
        # finished. We consider that success.
        if [0, 11].include?(status.exitstatus)
          return
        else
          exit status.exitstatus
        end
      end

      def inventory_uri
        @inventory_uri ||= URI.parse('https://localhost:8143/orchestrator/v1/inventory')
      end

      def request_object(nodes:, token_file:)
        token = File.read(token_file)
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
        Timeout.timeout(timeout) do
          loop do
            response = http.request(request)
            unless response.is_a? Net::HTTPSuccess
              raise "Unexpected result from orchestrator: #{response.class}\n#{response}"
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
  end
end

# Run the task if we got piped input. In order to enable unit testing, do not
# run the task if input is a tty.
unless STDIN.tty?
  upgrade = PEAdm::Task::PuppetInfraUpgrade.new(JSON.parse(STDIN.read))
  upgrade.execute!
end
