# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::pe_installer_source' do
  it 'exists' do
    is_expected.not_to be_nil
  end

  context 'when called with no parameters' do
    it { is_expected.to run.with_params.and_raise_error(Puppet::PreformattedError) }
  end
  context 'when called with absolute url and version' do
    result = {
      'url'      => 'https://url/puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'filename' => 'puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'version'  => '2019.8.12'
    }
    it { is_expected.to run.with_params('https://url/puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz', '2019.8.12').and_return(result) }
  end
  context 'when called with absolute url' do
    result = {
      'url'      => 'https://url/puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'filename' => 'puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'version'  => '2019.8.12'
    }
    it { is_expected.to run.with_params('https://url/puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz').and_return(result) }
  end
  context 'when called with url and version and platform' do
    result = {
      'url'      => 'https://url/puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'filename' => 'puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'version'  => '2019.8.12'
    }
    it { is_expected.to run.with_params('https://url/', '2019.8.12', 'el-8-x86_64').and_return(result) }
  end
  context 'when called without url and with version and platform' do
    result = {
      'url'      => 'https://s3.amazonaws.com/pe-builds/released/2019.8.12/puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'filename' => 'puppet-enterprise-2019.8.12-el-8-x86_64.tar.gz',
      'version'  => '2019.8.12'
    }
    it do
      is_expected.to run.with_params(nil, '2019.8.12', 'el-8-x86_64').and_return(result)
    end
  end
end
