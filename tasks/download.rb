#!/opt/puppetlabs/puppet/bin/ruby
#
# Puppet task for downloading a file from network to target location
#
# Parameters:
#   * source - The target location (http/https) to download the file from
#   * path - The location to save the file
#
require 'open3'
require 'puppet'

Puppet.initialize_settings

def download(source, path)
  stdout, stderr, status = Open3.capture3('/opt/puppetlabs/puppet/bin/curl', '-k', '-o', path, source)
  {
      stdout: stdout.strip,
      stderr: stderr.strip,
      exit_code: status.exitstatus,
  }

end

#params = JSON.parse(STDIN.read)
path = ENV['PT_path']
source = ENV['PT_source']
#path = params['path']
#source = params['source']

output = download(source, path)
if output[:exit_code].zero?
  puts output[:stdout]
else
  puts "There was a problem: #{output[:stderr]}"
end
