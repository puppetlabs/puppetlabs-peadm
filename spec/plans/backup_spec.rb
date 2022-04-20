require 'spec_helper'

describe 'peadm::backup' do
  include BoltSpec::Plans
  let(:params) { { 'primary_host' => 'primary' } }

  it 'runs with default params' do
    allow_apply
    pending('a lack of support for functions requires a workaround to be written')
    expect_task('peadm::get_peadm_config').always_return({ 'primary_postgresql_host' => 'postgres' })
    expect_out_message.with_params('# Backing up ca and ssl certificates')
    # The commands all have a timestamp in them and frankly its proved to hard with bolt spec to work this out
    allow_any_command
    allow_apply
    expect_out_message.with_params('# Backing up database pe-orchestrator')
    expect_out_message.with_params('# Backing up database pe-activity')
    expect_out_message.with_params('# Backing up database pe-rbac')
    expect_out_message.with_params('# Backing up classification')
    expect_task('peadm::backup_classification')
    expect(run_plan('peadm::backup', params)).to be_ok
  end
end
