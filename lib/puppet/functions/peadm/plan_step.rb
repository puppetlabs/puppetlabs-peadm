# frozen_string_literal: true

# @summary Run a named plan step once the requested starting step is reached
Puppet::Functions.create_function(:'peadm::plan_step', Puppet::Functions::InternalFunction) do
  # @param step_name Name of this step, compared with begin_at_step in the plan scope.
  # @param block The work to execute when this step is reached.
  # @return The block result when the step runs, or undef when skipped.
  dispatch :plan_step do
    scope_param
    param 'String', :step_name
    block_param
  end

  def plan_step(scope, step_name)
    first_step = scope.bound?('begin_at_step') ? scope['begin_at_step'] : nil
    first_step_reached = if first_step.nil? || scope.bound?('__first_plan_step_reached__')
                           true
                         elsif step_name == first_step
                           scope['__first_plan_step_reached__'] = true
                         else
                           false
                         end

    if first_step_reached
      call_function('out::message', "# Plan Step: #{step_name}")
      yield
    else
      call_function('out::message', "# Plan Step: #{step_name} - SKIPPING")
    end
  end
end
