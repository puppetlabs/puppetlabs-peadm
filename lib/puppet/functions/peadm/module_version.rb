# @summary Return the PEADM module version in the current environment
Puppet::Functions.create_function(:'peadm::module_version', Puppet::Functions::InternalFunction) do
  # @return [String] The installed PEADM module version.
  dispatch :module_version do
    scope_param
  end

  def module_version(scope)
    scope.compiler.environment.module('peadm').version
  end
end
