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

  # PE-45737: raised from no floor to a real enforced minimum, once that
  # ticket's test-writing gave the number something real to hold at --
  # measured 12.83% (161/1255 lines), up from the 4.29% PE-45655 baseline.
  #
  # PE-46426 added direct unit specs for the ten tasks and two functions
  # that were still at 0% (get_peadm_config.rb, check_pe_master_rules.rb,
  # cert_data.rb, code_sync_status.rb, check_legacy_compilers.rb,
  # code_manager_enabled.rb, classify_compilers.rb, backup_classification.rb,
  # get_group_rules.rb, cert_valid_status.rb, node_manager_yaml_location.rb,
  # module_version.rb -- see documentation/test-coverage.md). Measured via
  # `bundle exec rake spec:simplecov` (Ruby 3.1.7): 55.18% (575/1042 lines),
  # up from the 12.83% (161/1255 lines) PE-45737 baseline. 54 leaves a
  # small margin below that, the same discipline used for the original 12.
  # Still NOT close to 90%: every lib/puppet/functions/peadm/*.rb file
  # (including bolt_version.rb, which has a real passing spec) measures
  # 0.00% regardless of test effort, for the attribution reason documented
  # above; and six task files this ticket never named
  # (get_psql_version.rb, node_group_unpin.rb, pe_ldap_config.rb,
  # restore_classification.rb, transform_classification_groups.rb,
  # update_pe_master_rules.rb) remain completely untested and are real
  # follow-on work under PE-45224, not silently absorbed into this change.
  SimpleCov.minimum_coverage 54

  # Codecov upload needs a CODECOV_TOKEN this repo doesn't have configured.
  # Without dropping this formatter, every SIMPLECOV=yes run (local or CI)
  # still exits 0 -- SimpleCov::Formatter::MultiFormatter only warns on a
  # formatter error -- but it prints a warning and attempts (and fails) a
  # network upload on every run for no benefit. HTML + console output is
  # enough for now; wiring up Codecov upload is tracked as follow-on work,
  # not part of this change.
  SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::Console]
end
