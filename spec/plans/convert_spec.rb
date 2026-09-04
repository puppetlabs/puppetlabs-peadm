require 'spec_helper'

describe 'peadm::convert' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  let(:trustedjson) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted_facts.json')))
  end

  let(:params) do
    { 'primary_host' => 'primary', 'legacy_compilers' => ['pe_compiler_legacy'] }
  end

  before(:each) do
    allow_out_message
    allow_any_command
    allow_apply

    # For some reason, expect_plan() was not working??
    allow_plan('peadm::modify_certificate').always_return({})

    expect_task('peadm::cert_data').return_for_targets('primary' => trustedjson).be_called_times(2)
    expect_task('peadm::read_file').with_params('path' => '/opt/puppetlabs/server/pe_version').always_return({ 'content' => '2021.7.9' })
    expect_task('peadm::read_file').with_params('path' => '/etc/puppetlabs/enterprise/conf.d/pe.conf').always_return({ 'content' => '{}' })
    expect_task('peadm::get_group_rules').return_for_targets('primary' => { '_output' => '{"rules": []}' })
    expect_task('peadm::node_group_unpin').with_targets('primary').with_params({ 'node_certnames' => ['pe_compiler_legacy'], 'group_name' => 'PE Master' })
    expect_task('peadm::check_legacy_compilers').with_targets('primary').with_params({ 'legacy_compilers' => 'pe_compiler_legacy' }).return_for_targets('primary' => { '_output' => '' })
  end

  it 'single primary no dr valid' do
    allow_any_task

    expect(run_plan('peadm::convert', params)).to be_ok
  end

  it 'updates PE Master rules before the first Puppet run on compilers' do
    allow_task('peadm::wait_until_service_ready')

    call_order = []

    expect_task('peadm::update_pe_master_rules').return { |targets:, **|
      call_order << :update_pe_master_rules
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
    }

    expect_task('peadm::puppet_runonce').return { |targets:, **|
      call_order << :puppet_runonce
      Bolt::ResultSet.new(targets.map { |target| Bolt::Result.new(target, value: {}) })
    }.be_called_times(3)

    expect(run_plan('peadm::convert', params)).to be_ok

    # update_pe_master_rules must run before the puppet_runonce call that
    # reaches compilers, otherwise they can still be double-classified under
    # PE Master and hit the pe_format_urls() host/port mismatch (PE-44017).
    expect(call_order.index(:update_pe_master_rules)).to be < call_order.index(:puppet_runonce)
  end
end
