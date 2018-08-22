#!/opt/puppetlabs/puppet/bin/ruby

require 'json'
require 'open3'

def get2(command)
  output, exit_code = Open3.popen2({}, command, err: [:child, :out]) do |_i, o, w|
    out = o.read
    exit_code = w.value.exitstatus
    [out, exit_code]
  end

  { _output: output,
    exit_code: exit_code }
end

command = 'env PATH=/opt/puppetlabs/bin:$PATH puppet agent --onetime   --verbose \
  --no-daemonize --no-usecacheonfailure --no-splay --no-use_cached_catalog'

begin
  retries ||= 0
  result = get2(command)
  puts result.to_json
  exit result[:exit_code]
rescue
  retry if (retries += 1) < 3
end




