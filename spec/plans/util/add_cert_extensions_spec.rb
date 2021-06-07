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

  