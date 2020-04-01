require 'spec_helper'

describe 'peadm::determine_status' do
  let(:data) { JSON.parse(File.read(File.expand_path(File.join(fixtures, 'infrastatus.json')))) }
  let(:out) do
    JSON.parse(File.read(File.expand_path(File.join(fixtures, 'status.json'))))
  end

  it do
    is_expected.to run.with_params(data, false).and_return(out)
  end
end
