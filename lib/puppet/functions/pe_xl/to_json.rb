require 'json'

Puppet::Functions.create_function(:'pe_xl::to_json') do
  dispatch :to_json do
    param 'Variant[Hash,Array]', :data
  end

  def to_json(data)
    JSON.pretty_generate(data)
  end
end
