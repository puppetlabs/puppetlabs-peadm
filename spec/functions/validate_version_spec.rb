# frozen_string_literal: true
require 'spec_helper'

describe 'peadm::validate_version' do
  it '2020.3.0' do
    is_expected.to run.with_params('2020.3.0').and_raise_error(Puppet::ParseError, /This\ version\ of\ the/)
  end

  it '2019.9.0' do
    is_expected.to run.with_params('2019.9.0').and_return(true)
  end

  it '2019.8.4' do
    is_expected.to run.with_params('2019.8.4').and_return(true)
  end

  it '2019.8.0' do
    is_expected.to run.with_params('2019.8.0').and_return(true)
  end

  it '2019.7.1' do
    is_expected.to run.with_params('2019.7.1').and_return(true)
  end

  it '2018.1' do
    is_expected.to run.with_params('2018.1').and_raise_error(Puppet::ParseError, /This\ version\ of\ the/)
  end
end
