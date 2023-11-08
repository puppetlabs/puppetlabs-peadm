require 'spec_helper'

describe 'peadm::backup_ca' do
  include BoltSpec::Plans

  let(:params) { { 'target' => 'myserver.example.com' } }

  it 'will create backup directory and run puppet-backup command' do
    allow_apply
    expect_out_message.with_params('# Backing up ca and ssl certificates')
    allow_any_command
    expect(run_plan('peadm::backup_ca', params)).to be_ok
  end
end
