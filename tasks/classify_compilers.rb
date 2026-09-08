#!/usr/bin/env ruby

require 'json'
require 'open3'

# Class to classify compiler hosts as legacy or non-legacy based on the
# services reported by `puppet infra status`.
class ClassifyCompilers
  def initialize(params)
    @compiler_hosts = params['compiler_hosts']
  end

  def classify_compiler(services)
    if services.any? { |service| service['type'] == 'puppetdb' }
      :non_legacy
    else
      :legacy
    end
  end

  def execute!
    legacy_compilers = []
    non_legacy_compilers = []

    @compiler_hosts.each do |compiler|
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
  end
end

# Run the task unless an environment flag has been set, signaling not to. The
# environment flag is used to disable auto-execution and enable Ruby unit
# testing of this task.
unless ENV['RSPEC_UNIT_TEST_MODE']
  task = ClassifyCompilers.new(JSON.parse(STDIN.read))
  task.execute!
end
