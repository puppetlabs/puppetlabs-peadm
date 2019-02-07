#!/opt/puppetlabs/puppet/bin/ruby
#
# rubocop:disable Style/GlobalVars
require 'json'
require 'logger'
require 'open3'

# Parameters expected:
#   Hash
#     String mom_host
#     String database_host
#     Boolean debug
$params = JSON.parse(STDIN.read)

$logger = Logger.new(STDOUT)
$logger.level = ($params['debug']) ? Logger::DEBUG : Logger::INFO

def main; end

def run_command(*command)
  stdout, status = Open3.capture2(*command)
  unless status.success?
    @logger.error "while running command: #{command}"
    @logger.error stdout
  end
  stdout
end

main
