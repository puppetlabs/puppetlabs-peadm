# frozen_string_literal: true

require 'spec_helper'

# PE-47523: peadm_spec::verify_no_bootstrap_pe_conf is the acceptance check
# that install removed the bootstrap /tmp/pe.conf. It must fail when the file
# is there and when a node can't be checked, never pass without checking.
describe 'peadm_spec::verify_no_bootstrap_pe_conf' do
  include BoltSpec::Plans

  let(:inventory_data) do
    { 'targets' => [{ 'name' => 'primary' }, { 'name' => 'postgres1' }, { 'name' => 'replica' }] }
  end
  let(:check) { 'test ! -e /tmp/pe.conf' }

  before(:each) do
    allow_out_message
  end

  def stub_check(failing)
    expect_command(check).with_targets(['primary', 'postgres1', 'replica']).return do |targets:, **|
      Bolt::ResultSet.new(targets.map do |target|
        if failing.include?(target.name)
          Bolt::Result.new(target, error: { 'msg' => 'The command failed with exit code 1', 'kind' => 'puppetlabs.tasks/command-error' })
        else
          Bolt::Result.new(target, value: { 'stdout' => '', 'stderr' => '', 'exit_code' => 0 })
        end
      end)
    end
  end

  it 'passes when no node has /tmp/pe.conf' do
    stub_check([])

    expect(run_plan('peadm_spec::verify_no_bootstrap_pe_conf', {})).to be_ok
  end

  it 'fails, naming each node that still has /tmp/pe.conf or could not be checked' do
    stub_check(['primary', 'postgres1'])

    result = run_plan('peadm_spec::verify_no_bootstrap_pe_conf', {})

    expect(result).not_to be_ok
    expect(result.value.msg).to eq('/tmp/pe.conf is still present, or could not be checked, on primary, postgres1')
  end
end
