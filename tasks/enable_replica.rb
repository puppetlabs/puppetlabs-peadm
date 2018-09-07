#!/opt/puppetlabs/puppet/bin/ruby
#
# This task will enable the PE replica 
# This can only be run against the Puppet Master.
#
# Parameters:
#   * primary_master_replica - cert name of the PE master replica hosts.
#   * command_options - additional options to send to the the enable replica command.
#
require 'puppet'
require 'open3'

Puppet.initialize_settings

def cmd_run(command)
  stdout, stderr, status = Open3.capture3(command)
  {
    stdout: stdout.strip,
    stderr: stderr.strip,
    exit_code: status.exitstatus,
  }
end

results = {}
cmd_options = ENV['PT_command_options']
master_replica = ENV['PT_primary_master_replica']

if cmd_options
  command = "env PATH=/opt/puppetlabs/bin:$PATH puppet infrastructure enable replica  #{cmd_options} #{master_replica}"
else
  command = "env PATH=/opt/puppetlabs/bin:$PATH puppet infrastructure enable replica #{master_replica}"
end

begin
  retries ||= 0
  output = cmd_run(command)
  results[:result] = if output[:exit_code].zero?
                              "Puppet Infrastucture Enable Completed Successfully with #{retries} retry"
                            else
                              output
                            end
  raise output
rescue
  retry if (output[:exit_code] != 0) and ((retries += 1) < 2)
end

puts results.to_json
