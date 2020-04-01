require 'spec_helper'

# TODO test the error case, however due to an issue with boltspec 
# and functions we cannot do this right now.
# https://github.com/puppetlabs/bolt/issues/1688
describe 'peadm::target_name' do
  let(:target) do
    ['test-vm.puppet.vm']
  end
  #it { is_expected.to run.with_params(target).and_return('some_value') }
end
