# frozen_string_literal: true


Puppet::Functions.create_function(:'peadm::parsehocon') do
  dispatch :parsehocon do
    param 'String', :hocon_string
  end

  def parsehocon(hocon_string)
    require 'hocon/config_factory'

    data = Hocon::ConfigFactory.parse_string(hocon_string)
    data.resolve.root.unwrapped
  end
end
