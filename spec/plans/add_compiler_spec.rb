require 'spec_helper'

describe 'peadm::add_compiler' do
  include BoltSpec::Plans

  it 'accepts console_password without passing it to compiler provisioning' do
    allow_out_message
    expect_plan('peadm::add_compilers').with_params(
      'avail_group_letter' => 'A',
      'dns_alt_names' => nil,
      'compiler_hosts' => 'compiler',
      'primary_host' => 'primary',
      'primary_postgresql_host' => nil,
    )

    expect(run_plan('peadm::add_compiler',
                    'primary_host' => 'primary',
                    'compiler_host' => 'compiler',
                    'console_password' => 'existing-password')).to be_ok
  end
end
