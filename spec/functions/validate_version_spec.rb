# frozen_string_literal: true
require 'spec_helper'

describe 'peadm::validate_version' do
  context 'invalid PE versions' do
    it 'rejects PE versions that are too new' do
      is_expected.to run.with_params('2021.1.0').and_raise_error(Puppet::ParseError, /This\ version\ of\ the/)
    end

    it 'rejects PE versions that are too old' do
      is_expected.to run.with_params('2018.1.9').and_raise_error(Puppet::ParseError, /This\ version\ of\ the/)
    end
  end

  context 'valid PE versions' do
    it 'accepts the minimum supported version' do
      is_expected.to run.with_params('2019.7.0').and_return(true)
    end

    it 'accepts the newest supported version number' do
      is_expected.to run.with_params('2021.0.0').and_return(true)
    end

    it 'accepts a version in the middle' do
      is_expected.to run.with_params('2019.8.4').and_return(true)
    end
  end
end
