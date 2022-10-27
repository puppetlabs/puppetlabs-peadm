# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::assert_supported_pe_version' do
  context 'invalid PE versions' do
    it 'rejects PE versions that are too new' do
      is_expected.to run.with_params('2035.0.0').and_raise_error(Puppet::ParseError, %r{This\ version\ of\ the})
    end

    it 'rejects PE versions that are too old' do
      is_expected.to run.with_params('2018.1.9').and_raise_error(Puppet::ParseError, %r{This\ version\ of\ the})
    end
  end

  context 'valid PE versions' do
    it 'accepts the minimum supported version' do
      is_expected.to run.with_params('2019.7.0').and_return({ 'supported' => true })
    end

    it 'accepts the newest supported version' do
      is_expected.to run.with_params('2021.7.1').and_return({ 'supported' => true })
    end

    it 'accepts a version in the middle' do
      is_expected.to run.with_params('2019.8.7').and_return({ 'supported' => true })
    end
  end

  context 'unsafe versions' do
    it 'accepts PE versions that are too old' do
      is_expected.to run.with_params('2018.1.0', true).and_return({ 'supported' => false })
    end

    it 'accepts PE versions that are too new' do
      is_expected.to run.with_params('2035.0.0', true).and_return({ 'supported' => false })
    end

    it 'accepts PE versions that are in the supported range' do
      is_expected.to run.with_params('2019.8.7', true).and_return({ 'supported' => true })
    end
  end
end
