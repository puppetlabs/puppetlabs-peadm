require 'spec_helper'

describe 'peadm::upgrade' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  def allow_standard_non_returning_calls
    allow_apply
    allow_any_task
    allow_any_plan
    allow_any_command
    allow_out_message
  end

  let(:trusted_primary) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted-primary.json')))
  end

  let(:trusted_compiler) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted-compiler.json')))
  end

  it 'minimum variables to run' do
    allow_standard_non_returning_calls

    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })

    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary)

    expect(run_plan('peadm::upgrade',
                    'primary_host' => 'primary',
                    'version' => '2021.7.4')).to be_ok
  end

  it 'runs with a primary, compilers, but no replica' do
    allow_standard_non_returning_calls

    expect_task('peadm::read_file')
      .with_params('path' => '/opt/puppetlabs/server/pe_build')
      .always_return({ 'content' => '2021.7.3' })

    expect_task('peadm::cert_data').return_for_targets('primary' => trusted_primary,
                                                       'compiler' => trusted_compiler)

    expect(run_plan('peadm::upgrade',
                    'primary_host' => 'primary',
                    'compiler_hosts' => 'compiler',
                    'version' => '2021.7.4')).to be_ok
  end

  it 'fails if the primary uses the pcp transport' do
    allow_standard_non_returning_calls

    result = run_plan('peadm::upgrade',
                      'primary_host' => 'pcp://primary.example',
                      'version' => '2021.7.1')

    expect(result).not_to be_ok
    expect(result.value.kind).to eq('unexpected-transport')
    expect(result.value.msg).to match(%r{The "pcp" transport is not available for use with the Primary})
  end
end
