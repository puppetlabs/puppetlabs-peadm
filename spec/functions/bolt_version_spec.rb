# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::bolt_version' do
  it 'should_return_bolt_version' do
    stub_const('Bolt::VERSION', '2.45.0')
    is_expected.to run.and_return('2.45.0')
  end
end
