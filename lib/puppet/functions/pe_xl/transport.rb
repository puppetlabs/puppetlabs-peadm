# This function determine what transport is being used on a Target object. This
# is useful for excluding certain transports like when trying to send a large
# file over PCP
Puppet::Functions.create_function(:'pe_xl::transport') do
  dispatch :transport do
    param 'Target', :target
  end

  def transport(target)
    target.transport
  end
end
