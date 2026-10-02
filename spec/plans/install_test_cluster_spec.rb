require 'spec_helper'

# PE-46918: peadm::install passes an unset compiler_pool_address to
# peadm::subplans::configure, which defaults it to the primary's certname, so
# the acceptance harness has to forward a real pool address or agents on
# large/extra-large test clusters are served by the primary. The
# architectures covered here must stay in step with pe_acceptance_tests'
# REQUIRED_ROLES_BY_ARCHITECTURE, which decides who is given a pool address.
describe 'peadm_spec::install_test_cluster' do
  include BoltSpec::Plans

  let(:inventory_data) do
    {
      'targets' => [
        { 'name' => 'primary', 'vars' => { 'role' => 'primary' } },
        { 'name' => 'compiler1', 'vars' => { 'role' => 'compiler' } },
      ],
    }
  end

  # Runs the plan with peadm::install stubbed and returns the params it was
  # called with. bolt-spec's with_params is strict equality, so the params are
  # captured in the return block instead.
  def forwarded_install_params(architecture, extra = {})
    captured = nil
    allow_any_command
    allow_plan('peadm::install').return do |params:, **|
      captured = params
      Bolt::PlanResult.new({}, 'success')
    end
    result = run_plan('peadm_spec::install_test_cluster', {
      'architecture'     => architecture,
      'console_password' => 'puppetLabs123!',
      'version'          => '2025.12.0',
    }.merge(extra))
    expect(result).to be_ok
    expect(captured).not_to be_nil, 'peadm::install was never called with captured params'
    captured
  end

  ['large', 'large-with-dr', 'extra-large', 'extra-large-with-dr'].each do |architecture|
    it "forwards compiler_pool_address to peadm::install for #{architecture}" do
      params = forwarded_install_params(architecture, 'compiler_pool_address' => 'pool.example.com')

      expect(params['compiler_pool_address']).to eq('pool.example.com')
      expect(params['compiler_hosts']).not_to be_empty
    end
  end

  ['standard', 'standard-with-dr'].each do |architecture|
    it "does not forward compiler_pool_address for #{architecture}, which has no compilers" do
      params = forwarded_install_params(architecture, 'compiler_pool_address' => 'pool.example.com')

      expect(params).not_to have_key('compiler_pool_address')
    end
  end

  it 'leaves compiler_pool_address unset for peadm::install when none is given' do
    params = forwarded_install_params('large')

    expect(params['compiler_pool_address']).to be_nil
  end
end
