Puppet::Functions.create_function(:'peadm::module_version', Puppet::Functions::InternalFunction) do
  dispatch :module_version do
    scope_param
  end

  def module_version(scope)
    scope.compiler.environment.module('peadm').version
  end
end
