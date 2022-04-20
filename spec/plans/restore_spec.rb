require 'spec_helper'

describe 'peadm::restore' do
  include BoltSpec::Plans
  let(:params) { { 'primary_host' => 'primary', 'backup_timestamp' => '2022-03-29_16:57:41' } }

  it 'runs with default params' do
    allow_apply
    pending('a lack of support for functions requires a workaround to be written')
    expect_task('peadm::get_peadm_config').always_return({ 'primary_postgresql_host' => 'postgres' })
    expect_out_message.with_params('# Backing up ca and ssl certificates')
    # The commands all have a timestamp in them and frankly its proved to hard with bolt spec to work this out
    allow_any_command
    expect_out_message.with_params('# Restoring classification')
    expect_out_message.with_params('# Backed up current classification to /tmp/classification_backup.json')
    expect_out_message.with_params('# Restoring ca and ssl certificates')
    expect_out_message.with_params('# Restoring database pe-orchestrator')
    expect_out_message.with_params('# Restoring database pe-activity')
    expect_out_message.with_params('# Restoring database pe-rbac')
    expect_out_message.with_params('# Restoring classification')
    expect_task('peadm::backup_classification')
    expect(run_plan('peadm::restore', params)).to be_ok
  end
end
