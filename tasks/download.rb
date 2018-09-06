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

# set bad exit code as default, to be changed by download action
exit_code = 1

def download(source, path)
  stdout_head, stderr_head, status_head = Open3.capture3('/opt/puppetlabs/puppet/bin/curl', '-s', '-L', '--head', source)
  remote_size = stdout_head.match(/Content-Length: [0-9]+/).to_s.split(" ")[1].chomp.to_i
  local_size = File.size?(path)
  if local_size == remote_size
    {
        stdout: "File download not required, file sizes are the same.",
        stderr: "",
        exit_code: 0,
    }
  else
    stdout, stderr, status = Open3.capture3('/opt/puppetlabs/puppet/bin/curl', '-k', '-o', path, source)
    {
        stdout: stdout.strip,
        stderr: stderr.strip,
        exit_code: status.exitstatus,
    }
  end


end

path = ENV['PT_path']
source = ENV['PT_source']

output = download(source, path)
if output[:exit_code].zero?
  puts "Completed:  #{output[:stdout]}"
  return exit_code
else
  puts "There was a problem: #{output[:stderr]}"
  return exit_code
end
