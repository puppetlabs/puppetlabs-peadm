require 'spec_helper'

describe 'peadm::convert_hash' do
  let(:out) do
    [
      { 'type' => 'xl', 'status' => 'running' }, { 'type' => 'large', 'status' => 'failed' }
    ]
  end

  it do
    is_expected.to run.with_params(['type', 'status'], [['xl', 'running'], ['large', 'failed']])
                      .and_return(out)
  end
end
