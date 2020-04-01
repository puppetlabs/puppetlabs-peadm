require 'spec_helper'

describe 'peadm::convert_status' do
  let(:out) do
    [
      { 'type' => 'xl', 'status' => 'running' }, { 'type' => 'large', 'status' => 'failed' }
    ]
  end

  it { is_expected.to run.with_params(true).and_return("\e[32moperational\e[0m") }
  it { is_expected.to run.with_params(true, 0, false).and_return('operational') }
  it { is_expected.to run.with_params(1, 2, false).and_return('degraded') }
  it { is_expected.to run.with_params(2, 2, false).and_return('failed') }
  it { is_expected.to run.with_params(0, 2, false).and_return('operational') }
end
