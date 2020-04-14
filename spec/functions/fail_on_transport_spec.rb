# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::fail_on_transport' do
  let(:nodes) do
    'some_value_goes_here'
  end
  let(:transport) do
    'some_value_goes_here'
  end

  xit { is_expected.to run.with_params(nodes, transport).and_return('some_value') }
end
