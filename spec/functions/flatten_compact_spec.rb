# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::flatten_compact' do
  let(:input) do
    [1, 2, 3, nil, 4, 5, 6, nil, 'ds', '']
  end

  it { is_expected.to run.with_params(input).and_return([1, 2, 3, 4, 5, 6, 'ds', '']) }
end
