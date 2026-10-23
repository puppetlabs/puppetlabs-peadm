require 'bolt'

# @summary Return the version of the running Bolt library
Puppet::Functions.create_function(:'peadm::bolt_version') do
  # @return [String] The Bolt version.
  def bolt_version
    Bolt::VERSION
  end
end
