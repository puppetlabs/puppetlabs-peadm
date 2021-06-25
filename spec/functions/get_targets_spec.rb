# frozen_string_literal: true

require 'spec_helper'
# TODO: test the error case, however due to an issue with boltspec
# and functions we cannot do this right now.
# https://github.com/puppetlabs/bolt/issues/1688
describe 'peadm::get_targets' do
  let(:pre_condition) do
    'type TargetSpec = Variant[String[1], Target, Array[TargetSpec]]'
  end

  context 'undefined or empty arguments' do
    it { is_expected.to run.with_params([], 1).and_return([]) }
    it { is_expected.to run.with_params([]).and_return([]) }
    it { is_expected.to run.with_params(:undef, 1).and_return([]) }
    it { is_expected.to run.with_params(:undef).and_return([]) }
  end

  context 'string arguments' do
    it 'converts a string input to a Target array without count' do
      skip 'Being able to stub the get_targets() function'
      is_expected.to run.with_params('fqdn').and_return(['fqdn'])
    end
    it 'converts a string input to a Target array with count' do
      skip 'Being able to stub the get_targets() function'
      is_expected.to run.with_params('fqdn', 1).and_return(['fqdn'])
    end
  end

  context 'array arguments' do
    it 'converts an array input to a Target array without count' do
      skip 'Being able to stub the get_targets() function'
      is_expected.to run.with_params(['fqdn']).and_return(['fqdn'])
    end
    it 'converts an array input to a Target array with count' do
      skip 'Being able to stub the get_targets() function'
      is_expected.to run.with_params(['fqdn'], 1).and_return(['fqdn'])
    end
  end
end
