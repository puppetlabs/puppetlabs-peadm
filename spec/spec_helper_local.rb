# frozen_string_literal: true

# Load the BoltSpec library
require 'bolt_spec/plans'

# Configure Puppet and Bolt for testing
BoltSpec::Plans.init

# This environment variable can be read by Ruby Bolt tasks to prevent unwanted
# auto-execution, enabling easy unit testing.
ENV['RSPEC_UNIT_TEST_MODE'] ||= 'TRUE'

# Matcher to aid in testing plans which call functions that need to be stubbed.
# This matcher enables functions without an explicit call_function() expectation
# to invoke the original. If it is not called, and a call_function() expectation
# is given, a test will error with "unexpected arguments".
#
# Example usage:
#
#   it { is_expected.to allow_function_calls }
#
RSpec::Matchers.define :allow_function_calls do
  match do
    matcher = receive(:call_function).with(any_args).and_call_original
    allow_any_instance_of(Puppet::Pops::Evaluator::EvaluatorImpl).to(matcher)
  end
end

# Matcher to aid in testing plans which call functions that need to be stubbed with
# an expected return value.
#
# Example usage:
#
#   it "demonstrates call_function matcher usage" do
#     is_expected.to allow_function_calls
#     is_expected.to call_function('peadm::one').and_return
#     is_expected.to call_function('peadm::two').with_arguments(1, 2).and_return(3)
#     is_expected.to call_function('peadm::three').with_arguments(4).exactly(5).times.and_return(6)
#     expect(run_plan('peadm::four', {})).to be_ok
#   end
#
RSpec::Matchers.define :call_function do |name|
  chain(:with_arguments) { |*args| @with_arguments = args }
  chain(:and_return) { |val = nil| @and_return = val || :undef }
  chain(:at_least) { |times| @at_least = times }
  chain(:exactly) { |times| @exactly = times }
  chain(:times) { @times = true }
  chain(:time) { @times = true }

  match do
    if @and_return.nil?
      raise 'Must use .and_return() when mocking functions'
    end

    matcher = receive(:call_function)

    if @with_arguments
      matcher.with(name, @with_arguments, any_args)
    else
      matcher.with(name, any_args)
    end
    if @at_least
      raise 'Must end with e.g. at_least(n).times' unless @times
      matcher.at_least(@at_least).times
    end
    if @exactly
      raise 'Must end with e.g. exactly(n).times' unless @times
      matcher.exactly(@exactly).times
    end

    matcher.and_return(@and_return)

    expect_any_instance_of(Puppet::Pops::Evaluator::EvaluatorImpl).to(matcher)
  end
end
