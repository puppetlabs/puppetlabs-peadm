# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

describe 'PEADM installation console password cleanup' do
  include BoltSpec::Plans

  let(:params) do
    {
      'primary_host' => 'primary',
      'console_password' => 'installation-password',
      'license_key_content' => 'license-to-preserve',
      'r10k_private_key_content' => "-----BEGIN PRIVATE KEY-----\nkey\n-----END PRIVATE KEY-----",
      'pe_conf_data' => { 'database_password' => 'database-password-to-preserve' },
    }
  end

  it 'cleans a local params file without contacting targets and can run again' do
    Dir.mktmpdir('peadm-plan-test') do |dir|
      path = File.join(dir, 'params.json')
      File.write(path, JSON.generate(params))
      execute_no_task
      result = run_plan('peadm::remove_secrets_local', params.merge('params_file' => path))
      expect(result).to be_ok
      expect(result.value['changed']).to be(true)
      cleaned = JSON.parse(File.read(path))
      expect(cleaned).to eq(params.reject { |key, _| key == 'console_password' })
      expect(run_plan('peadm::remove_secrets_local', cleaned.merge('params_file' => path))).to be_ok
    end
  end

  it 'runs only the fixed-path cleanup task on the primary without sending installer secrets' do
    expect_task('peadm::remove_console_password').with_targets('primary').with_params({})
                                                 .always_return('changed' => true, 'removed_keys' => ['console_admin_password'])
    expect(run_plan('peadm::remove_secrets_primary', params)).to be_ok
  end

  it 'accepts params after the local console password has been removed' do
    expect_task('peadm::remove_console_password').with_targets('primary').with_params({})
                                                 .always_return('changed' => false, 'reason' => 'missing')
    expect(run_plan('peadm::remove_secrets_primary', params.reject { |key, _| key == 'console_password' })).to be_ok
  end
end
