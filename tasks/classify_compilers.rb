#!/usr/bin/env ruby

require 'json'
require 'open3'

def classify_compiler(services)
  if services.any? { |service| service['type'] == 'puppetdb' }
    :non_legacy
  else
    :legacy
  end
end

params = JSON.parse(STDIN.read)
compiler_hosts = params['compiler_hosts']

legacy_compilers = []
non_legacy_compilers = []

compiler_hosts.each do |compiler|
  cmd = "puppet infra status --host #{compiler} --format=json"
  stdout, stderr, status = Open3.capture3(cmd)

  if status.success?
    services = JSON.parse(stdout)
    classification = classify_compiler(services)

    if classification == :legacy
      legacy_compilers << compiler
    else
      non_legacy_compilers << compiler
    end
  else
    STDERR.puts "Error running command for #{compiler}: #{stderr}"
  end
end

result = {
  'legacy_compilers' => legacy_compilers,
  'compilers' => non_legacy_compilers
}

puts result.to_json
