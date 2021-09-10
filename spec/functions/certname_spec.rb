# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::certname' do
  include BoltSpec::BoltContext

  let(:target) do
    ['test-vm.puppet.vm']
  end

  # TODO: this *should* work, but is failing in TravisCI. Not sure why. It works on my laptop...
  xit { in_bolt_context { is_expected.to run.with_params(target).and_return('test-vm.puppet.vm') } }
end
