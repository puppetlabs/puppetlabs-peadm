# frozen_string_literal: true

require 'spec_helper'

# TODO: test the error case, however due to an issue with boltspec
# and functions we cannot do this right now.
# https://github.com/puppetlabs/bolt/issues/1688
describe 'peadm::certname' do
  include BoltSpec::BoltContext

  let(:target) do
    ['test-vm.puppet.vm']
  end

  it { in_bolt_context { is_expected.to run.with_params(target).and_return('test-vm.puppet.vm') } }
end
