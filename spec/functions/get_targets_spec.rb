require 'spec_helper'
# TODO test the error case, however due to an issue with boltspec 
# and functions we cannot do this right now.
# https://github.com/puppetlabs/bolt/issues/1688
describe 'peadm::get_targets' do
  let(:spec) do
    'some_value_goes_here'
  end
  let(:count) do
    'some_value_goes_here'
  end
  #it { is_expected.to run.with_params(spec,count).and_return('some_value') }
end
