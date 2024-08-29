# frozen_string_literal: true

require 'spec_helper'

describe 'peadm::get_node_group_environment' do
  include BoltSpec::BoltContext
  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end
  let(:primary) do
    ['test-vm.puppet.vm']
  end

  context 'returns production on empty pe.conf' do
    it do
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
      is_expected.to run.with_params(primary).and_return('production')
    end
  end

  context 'returns production on non-empty pe.conf with unrelated settings' do
    it do
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{"foo": true}' })
      is_expected.to run.with_params(primary).and_return('production')
    end
  end
  context 'returns environment from pe.conf when set twice correctly' do
    it do
      pe = '{"pe_install::install::classification::pe_node_group_environment": "foo", "puppet_enterprise::master::recover_configuration::pe_environment": "foo"}'
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => pe })
      is_expected.to run.with_params(primary).and_return('foo')
    end
  end
  context 'fails when both PE options are different' do
    it do
      pe = '{"pe_install::install::classification::pe_node_group_environment": "foo", "puppet_enterprise::master::recover_configuration::pe_environment": "bar"}'
      expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => pe })
      is_expected.to run.with_params(primary).and_raise_error(Puppet::PreformattedError,
%r{pe_install::install::classification::pe_node_group_environment and puppet_enterprise::master::recover_configuration::pe_environment})
    end
  end
end
