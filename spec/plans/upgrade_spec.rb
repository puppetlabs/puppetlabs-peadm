require 'spec_helper'

describe 'peadm::upgrade' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  let(:trustedjson) do
    JSON.parse File.read(File.expand_path(File.join(fixtures, 'plans', 'trusted_facts.json')))
  end

  it 'minimum variables to run' do
    allow_apply
    allow_any_task
    allow_any_plan
    allow_any_command
    allow_out_message

    expect_task('peadm::cert_data').return_for_targets('primary' => trustedjson)
    expect_task('peadm::read_file').always_return({ 'content' => 'mock' })

    expect(run_plan('peadm::upgrade', 'primary_host' => 'primary', 'version' => '2019.8.6')).to be_ok
  end
end
