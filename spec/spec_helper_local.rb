# frozen_string_literal: true

# Load the BoltSpec library
require 'bolt_spec/plans'

# Configure Puppet and Bolt for testing
BoltSpec::Plans.init

# This environment variable can be read by Ruby Bolt tasks to prevent unwanted
# auto-execution, enabling easy unit testing.
ENV['RSPEC_UNIT_TEST_MODE'] ||= 'TRUE'

if defined?(SimpleCov)
  # puppetlabs_spec_helper's built-in SimpleCov setup (SIMPLECOV=yes) only
  # tracks lib/**/*.rb by default, so tasks/*.rb never shows up even as an
  # explicit 0% gap. Widen it to cover the Ruby-side surface PE-45655 cares
  # about (tasks/*.rb and lib/puppet/functions/peadm/*.rb).
  SimpleCov.track_files('{lib/**/*.rb,tasks/*.rb}')

  # Codecov upload needs a CODECOV_TOKEN this repo doesn't have configured.
  # Without dropping this formatter, every SIMPLECOV=yes run (local or CI)
  # still exits 0 -- SimpleCov::Formatter::MultiFormatter only warns on a
  # formatter error -- but it prints a warning and attempts (and fails) a
  # network upload on every run for no benefit. HTML + console output is
  # enough for now; wiring up Codecov upload is tracked as follow-on work,
  # not part of this change.
  SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::Console]
end
