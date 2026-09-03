# frozen_string_literal: true

# Load the BoltSpec library
require 'bolt_spec/plans'

# Configure Puppet and Bolt for testing
BoltSpec::Plans.init

# This environment variable can be read by Ruby Bolt tasks to prevent unwanted
# auto-execution, enabling easy unit testing.
ENV['RSPEC_UNIT_TEST_MODE'] ||= 'TRUE'

if defined?(SimpleCov)
  # puppetlabs_spec_helper's built-in SimpleCov setup (SIMPLECOV=yes) already
  # tracks lib/**/*.rb (including lib/puppet/functions/peadm/*.rb) by default,
  # but not tasks/*.rb, so task files never show up even as an explicit 0%
  # gap. Widen the glob to add tasks/*.rb to what's already covered.
  SimpleCov.track_files('{lib/**/*.rb,tasks/*.rb}')

  # PE-45737: raised from no floor to a real enforced minimum, once this
  # ticket's test-writing gave the number something real to hold at --
  # measured 12.83% (161/1255 lines) after this ticket's work, up from the
  # 4.29% PE-45655 baseline. 12 leaves a small margin below the measured
  # value. This is intentionally NOT close to the PE-45737 acceptance
  # criterion of 90%: the files still at 0% (get_peadm_config.rb,
  # check_pe_master_rules.rb, cert_data.rb, and others -- see
  # documentation/test-coverage.md) were never named in this ticket's scope,
  # and covering them is tracked as follow-on work, not silently expanded
  # into this change.
  SimpleCov.minimum_coverage 12

  # Codecov upload needs a CODECOV_TOKEN this repo doesn't have configured.
  # Without dropping this formatter, every SIMPLECOV=yes run (local or CI)
  # still exits 0 -- SimpleCov::Formatter::MultiFormatter only warns on a
  # formatter error -- but it prints a warning and attempts (and fails) a
  # network upload on every run for no benefit. HTML + console output is
  # enough for now; wiring up Codecov upload is tracked as follow-on work,
  # not part of this change.
  SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::Console]
end
