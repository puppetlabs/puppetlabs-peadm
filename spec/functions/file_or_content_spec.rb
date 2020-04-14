# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::file_or_content' do
  let(:param_name) do
    'some_value_goes_here'
  end
  let(:file) do
    'some_value_goes_here'
  end
  let(:content) do
    'some_value_goes_here'
  end

  xit { is_expected.to run.with_params(param_name, file, content).and_return('some_value') }
end
