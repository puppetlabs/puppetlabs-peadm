# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::certname' do
  include BoltSpec::BoltContext
  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end
  let(:target) do
    ['test-vm.puppet.vm']
  end

  it { is_expected.to run.with_params(target).and_return('test-vm.puppet.vm') }
end
