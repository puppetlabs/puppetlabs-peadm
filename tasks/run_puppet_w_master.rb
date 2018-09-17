#!/opt/puppetlabs/puppet/bin/ruby
#
# This will copy the puppet.conf removing the server_list and
# run puppet agent pointing at identified puppet master.
#
# Parameters:
#   * puppet_master         - The puppet master to run puppet against
#   * debug                 - logger setting to debug
#

require 'open3'
require 'logger'
require 'tempfile'

$debug = ENV['PT_debug']

$logger = Logger.new(STDOUT)
$logger.level = $debug ? Logger::DEBUG : Logger::INFO

# set exit_code to 1 for final failure check
$exit_code = 1

# array of acceptable exit codes for the installer process
$installer_acceptable_codes = [ 0, 6 ]

def run_command(*args)
  command = args[0]
  codes = args[1]
  if ! codes
    codes = [ 0 ]
  end
  if $debug == 'true'
    $logger.debug "Beginning to run #{command}"
  end
  stdout, stderr, status = Open3.capture3("#{command}")
  if $debug == 'true'
    $logger.debug "Exit code was #{status.exitstatus}"
  end
  unless codes.include? status.exitstatus
    $logger.error "while running command: #{command}"
    $logger.error stdout
  end
  {
      stdout: stdout.strip,
      stderr: stderr.strip,
      exit_code: status.exitstatus,
  }
end

$puppet_master = ENV['PT_puppet_master']
$tmp_puppet_config = Tempfile.new('puppet_conf')

def read_conf(config_file)
  file = File.open(config_file, "r")
  data = file.read
  file.close
  return data
end

def tmp_puppetconf()
  conf_content = read_conf('/etc/puppetlabs/puppet/puppet.conf').gsub(%r{^server_list.*\n?},'')
  conf_content = conf_content.gsub(%r{^server .*\n?},"server = #{$puppet_master}\n")
  $tmp_puppet_config << conf_content
  $tmp_puppet_config.rewind
end

def cleanup_tmp_puppetconf()
  $tmp_puppet_config.close
  $tmp_puppet_config.unlink
end

def main
  tmp_puppetconf
  puppet_command = "/opt/puppetlabs/bin/puppet agent \
    --onetime \
    --verbose \
    --no-daemonize \
    --no-usecacheonfailure \
    --no-splay \
    --no-use_cached_catalog \
    --config #{$tmp_puppet_config.path}"
  output = run_command(puppet_command)
  if output[:exit_code] == 0
    puts output[:stdout]
    return output[:exit_code]
  else
    @logger.error "while running command: #{puppet_command}"
    @logger.error output[:stderr]
    return $exit_code
  end
   puts output
end

# check if vars are set
if ! $puppet_master
  $logger.error "Required params not provided."
  $logger.error 'Please ensure ENV["PT_puppet_master"] are set.'
  exit 1
end

main
