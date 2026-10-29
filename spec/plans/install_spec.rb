require 'spec_helper'

describe 'peadm::install' do
  include BoltSpec::Plans

  describe 'basic functionality' do
    it 'runs successfully with the minimum required parameters' do
      allow_out_message
      expect_plan('peadm::subplans::install')
      expect_plan('peadm::subplans::configure')
      expect(run_plan('peadm::install', 'primary_host' => 'primary', 'console_password' => 'puppetLabs123!', 'version' => '2021.7.9')).to be_ok
    end
  end

  describe 'cloud_database_host plumbing' do
    # bolt-spec's `with_params` compares for strict equality and does not
    # honour rspec matchers like hash_including, so fine-grained param
    # assertions are awkward here. Confirm at minimum that providing
    # cloud_database_host does not break the install plan; the more
    # specific tests for the parameter's effect live in
    # spec/classes/setup/node_manager_spec.rb (verifying what the value
    # produces) and the configure subplan accepts the same parameter
    # signature by virtue of compiling.
    it 'accepts cloud_database_host and runs the plan to completion' do
      allow_out_message
      expect_plan('peadm::subplans::install')
      expect_plan('peadm::subplans::configure')
      expect(run_plan('peadm::install',
        'primary_host'        => 'primary',
        'console_password'    => 'puppetLabs123!',
        'version'             => '2021.7.9',
        'cloud_database_host' => 'cloud-sql.example.com')).to be_ok
    end
  end

  # PE-47523: console_password stays a plain String. BoltSpec's run_plan
  # wraps Sensitive-typed parameters the way the CLI does, so only a call
  # through the run_plan() function, as pecdm, peadm::migrate and
  # peadm_spec::install_test_cluster make, would fail if the signature
  # changed to Sensitive.
  describe 'console_password passed by another plan' do
    let(:inventory_data) { { 'targets' => [{ 'name' => 'primary', 'vars' => { 'role' => 'primary' } }] } }

    it 'accepts a plain String' do
      allow_any_command
      allow_any_task
      allow_out_message
      expect_plan('peadm::subplans::install')
      expect_plan('peadm::subplans::configure')

      expect(run_plan('peadm_spec::install_test_cluster',
                      'architecture'     => 'standard',
                      'console_password' => 'puppetLabs123!',
                      'version'          => '2023.8.10')).to be_ok
    end
  end
end
