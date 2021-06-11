# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::misc::divert_code_manager' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:each) do
    BoltSpec::Plans.init
  end


    it 'divert code manager runs' do
      expect_task('peadm::divert_code_manager')
      expect(run_plan('peadm::misc::divert_code_manager', 'primary_host' => 'primary')).to be_ok
    end
end