require 'spec_helper'

describe 'peadm::restore_ca' do
  include BoltSpec::Plans

  let(:params) do
    {
      'target' => 'myserver.example.com',
      'file_path' => '/tmp/backup_ca.tgz'
    }
  end

  it 'will run puppet-backup command' do
    expect_out_message.with_params('# Restoring ca and ssl certificates')
    allow_any_command
    expect(run_plan('peadm::restore_ca', params)).to be_ok
  end
end
