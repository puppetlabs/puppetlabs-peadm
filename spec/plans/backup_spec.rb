require 'spec_helper'

describe 'peadm::backup' do
  include BoltSpec::Plans
  let(:params) { { 'primary_host' => 'primary' } }

  it 'runs with default params' do
    allow_apply_prep
    allow_apply
    expect_out_message.with_params('# Backing up ca and ssl certificates')
    # The commands all have a timestamp in them and frankly its prooved to hard with bolt spec to work this out
    allow_any_command
    expect_out_message.with_params('# Backing up database pe-orchestrator')
    expect_out_message.with_params('# Backing up database pe-activity')
    expect_out_message.with_params('# Backing up database pe-rbac')
    expect_out_message.with_params('# Backing up classification')
    expect_task('peadm::backup_classification')
    expect(run_plan('peadm::backup', params)).to be_ok
  end
end
