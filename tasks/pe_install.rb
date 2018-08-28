#!/opt/puppetlabs/puppet/bin/ruby
#
# This stanza configures PuppetDB to quickly fail on start. This is desirable
# in situations where PuppetDB WILL fail, such as when PostgreSQL is not yet
# configured, and we don't want to let PuppetDB wait five minutes before
# giving up on it.
#
# Parameters:
#   * shortcircuit_puppetdb - configures PuppetDB to quickly fail on start
#   * tarball               - The location of the pe install package
#   * peconf               - The location of the pe.conf file to use for install
#   * debug                 - logger setting to debug
#

require 'open3'
require 'logger'
require 'json'

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

$shortcircuit = ENV['PT_shortcircuit_puppetdb']
$tarball = ENV['PT_tarball']
$pe_conf = ENV['PT_peconf']

def start_shortciruit
  run_command('mkdir /etc/systemd/system/pe-puppetdb.service.d', [ 0, 1 ] )
  run_command('cat > /etc/systemd/system/pe-puppetdb.service.d/10-shortcircuit.conf <<-EOF
           [Service]
           TimeoutStartSec=1
           TimeoutStopSec=1
    EOF')
  run_command('systemctl daemon-reload')
end

def stop_shortciruit()
  run_command('rm /etc/systemd/system/pe-puppetdb.service.d/10-shortcircuit.conf')
  run_command('systemctl daemon-reload')
end

# check if vars are set
if ! $shortcircuit or ! $tarball or ! $pe_conf
  $logger.error "Required params not provided."
  $logger.error 'Please ensure ENV["PT_shortcircuit_puppetdb"], ENV["PT_tarball"], ENV["PT_pe_conf"] are set.'
  exit 1
end

# start script with valid input
if $shortcircuit
  start_shortciruit
end

def main
  tar_path = File.dirname($tarball)
  Dir.chdir tar_path
  run_command('mkdir puppet-enterprise', [ 0, 1 ])
  run_command("tar -xzf #{$tarball} -C puppet-enterprise --strip-components 1")
  Dir.chdir "#{tar_path}/puppet-enterprise"
  install_command = "#{tar_path}/puppet-enterprise/puppet-enterprise-installer -c #{$pe_conf}"
  output = run_command(install_command, $installer_acceptable_codes)
  if output[:exit_code] 
    puts output[:stdout]
    if $shortcircuit
      stop_shortciruit
    end
    return output[:exit_code]
  else
    @logger.error "while running command: #{command}"
    @logger.error output[:stderr]
    if $shortcircuit
      stop_shortciruit
    end
    return $exit_code
  end
end

main
