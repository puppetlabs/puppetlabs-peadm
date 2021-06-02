# spec/spec_helper.rb

# Load the BoltSpec library
require 'bolt_spec/plans'

describe 'peadm::provision' do
    # Include the BoltSpec library functions
    include BoltSpec::Plans
  
    # Configure Puppet and Bolt before running any tests
    before(:all) do
      BoltSpec::Plans.init
    end
end