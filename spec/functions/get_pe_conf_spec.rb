# frozen_string_literal: true

require 'spec_helper'

# pe.conf holds console_admin_password on a PEADM-installed primary, so
# peadm::get_pe_conf reads it as Sensitive (PE-47523) and returns it parsed.
describe 'peadm::get_pe_conf' do
  include BoltSpec::BoltContext

  around(:each) do |example|
    in_bolt_context do
      example.run
    end
  end

  let(:target) { Bolt::Target.from_hash({ 'name' => 'primary' }, Bolt::Inventory.empty) }

  it 'returns the parsed pe.conf' do
    expect_pe_conf_reads('{"console_admin_password": "pw-canary", "puppet_enterprise::puppet_master_host": "primary"}')

    is_expected.to run.with_params(target).and_return(
      'console_admin_password'                => 'pw-canary',
      'puppet_enterprise::puppet_master_host' => 'primary',
    )
  end

  it 'returns an empty Hash when there is no pe.conf' do
    expect_task('peadm::read_file').return { |targets:, **| sensitive_read_file_result(targets, nil) }

    is_expected.to run.with_params(target).and_return({})
  end
end
