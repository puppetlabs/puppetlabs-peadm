# frozen_string_literal: true

require 'spec_helper'

# peadm::plan_step is declared with scope_param + block_param, a combination
# no other function spec in this repo exercises. Per the write-tests
# guidance we bypass the Puppet dispatcher entirely and call the raw
# function instance (`subject.func`) directly, supplying our own minimal
# scope double that only implements the three methods plan_step actually
# uses: bound?, [] and []=. This lets us fully control whether
# 'begin_at_step' and the sticky '__first_plan_step_reached__' flag are
# bound, which would be very awkward to arrange through a real compiled
# Puppet::Parser::Scope.
#
# plan_step also calls out::message internally, which requires Puppet[:tasks]
# to be true and a bolt_executor to be looked up - both provided by
# BoltSpec::BoltContext#in_bolt_context, the same helper other peadm function
# specs (e.g. fail_on_transport_spec, certname_spec) use.
describe 'peadm::plan_step' do
  include BoltSpec::BoltContext

  around :each do |example|
    in_bolt_context do
      example.run
    end
  end

  # Minimal scope double implementing only what plan_step reads/writes.
  # rubocop:disable RSpec/InstanceVariable -- this is a plain Ruby class
  # implementing a scope double, not example-group test state; the cop's
  # heuristic can't distinguish the two.
  class FakeScope
    def initialize(vars = {})
      @vars = vars
    end

    def bound?(name)
      @vars.key?(name)
    end

    def [](name)
      @vars[name]
    end

    def []=(name, value)
      @vars[name] = value
    end
  end
  # rubocop:enable RSpec/InstanceVariable

  # rubocop:disable RSpec/NamedSubject
  context 'when begin_at_step is not bound at all' do
    it 'always yields the block, regardless of step name' do
      scope = FakeScope.new
      expect_out_message.with_params('# Plan Step: any-step')

      yielded = false
      subject.func.plan_step(scope, 'any-step') { yielded = true }

      # Catches a mutation that makes the "no begin_at_step" branch
      # conditionally skip the block (e.g. treating nil as a step name that
      # must match).
      expect(yielded).to be true
      executor.assert_call_expectations
    end
  end

  context 'when begin_at_step is bound and the current step matches it' do
    it 'yields the block and sets the sticky first-step-reached flag' do
      scope = FakeScope.new('begin_at_step' => 'step-a')
      expect_out_message.with_params('# Plan Step: step-a')

      yielded = false
      subject.func.plan_step(scope, 'step-a') { yielded = true }

      # Catches a mutation that fails to yield on the matching step.
      expect(yielded).to be true
      # Catches a mutation that fails to set (or sets under the wrong key)
      # the sticky flag, which would silently break every later
      # begin_at_step-driven resume step (see the sticky-behavior test below).
      expect(scope.bound?('__first_plan_step_reached__')).to be true
      executor.assert_call_expectations
    end
  end

  context 'when begin_at_step is bound and the current step does not match it yet' do
    it 'does not yield the block and emits a SKIPPING message' do
      scope = FakeScope.new('begin_at_step' => 'step-b')
      expect_out_message.with_params('# Plan Step: step-a - SKIPPING')

      yielded = false
      subject.func.plan_step(scope, 'step-a') { yielded = true }

      # Catches a mutation that yields even when the step hasn't been reached.
      expect(yielded).to be false
      # Catches a mutation that sets the sticky flag prematurely, which would
      # cause every subsequent step to incorrectly run.
      expect(scope.bound?('__first_plan_step_reached__')).to be false
      executor.assert_call_expectations
    end
  end

  context 'sticky behavior once the first step has been reached' do
    it 'yields for a later, non-matching step name because the sticky flag short-circuits the match check' do
      # Simulate having already passed the matching step in an earlier call.
      scope = FakeScope.new(
        'begin_at_step' => 'step-a',
        '__first_plan_step_reached__' => true,
      )
      expect_out_message.with_params('# Plan Step: step-z')

      yielded = false
      subject.func.plan_step(scope, 'step-z') { yielded = true }

      # This is the crux of begin_at_step's whole purpose: once a manual
      # plan resume has reached its starting step, every following step
      # must run regardless of name. A mutation that re-checks
      # `step_name == first_step` even when the sticky flag is already set
      # would cause this to incorrectly emit "SKIPPING" and fail to yield,
      # silently breaking every begin_at_step-driven manual plan resume.
      expect(yielded).to be true
      executor.assert_call_expectations
    end
  end
  # rubocop:enable RSpec/NamedSubject
end
