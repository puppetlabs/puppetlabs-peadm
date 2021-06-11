# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::util::insert_csr_extension_requests' do
  # Include the BoltSpec library functions
  include BoltSpec::Plans

  # Configure Puppet and Bolt before running any tests
  before(:each) do
    BoltSpec::Plans.init
  end

  it 'Runs csr read and write file for each host' do
    expect_task('peadm::read_file').be_called_times(2)
    expect_task('peadm::mkdir_p_file').be_called_times(2)
    expect(run_plan('peadm::util::insert_csr_extension_requests', 'targets' => 'foo,bar', 'extension_requests' => {'pe_role' => 'puppet/server' })).to be_ok
  end

end