# @api private
#
# @summary Install a new PEADM component
# @param targets _ The hostname of the new component server
# @param primary_host _ The hostname the primary Puppet server
# @param avail_group_letter _ Either A or B; whichever of the two letter designations the component is assigned to
# @param dns_alt_names _ A comma_separated list of DNS alt names for the component
# @param role _ Optional PEADM role the component will serve
plan peadm::subplans::component_install(
  Peadm::SingleTargetSpec                $targets,
  Peadm::SingleTargetSpec                $primary_host,
  Enum['A', 'B']                         $avail_group_letter,
  Optional[Variant[String[1], Array]]    $dns_alt_names = undef,
  Optional[String[1]]                    $role          = undef
) {
  $component_target          = peadm::get_targets($targets, 1)
  $primary_target            = peadm::get_targets($primary_host, 1)

  # Set pp_auth_role instead of peadm_role for compiler role
  if $role == 'pe_compiler' {
    $certificate_extensions = {
      peadm::oid('pp_auth_role')             => 'pe_compiler',
      peadm::oid('peadm_availability_group') => $avail_group_letter,
    }
  } elsif $role == 'pe_compiler_legacy' {
    $certificate_extensions = {
      peadm::oid('pp_auth_role')             => 'pe_compiler_legacy',
      peadm::oid('peadm_availability_group') => $avail_group_letter,
    }
  } else {
    $certificate_extensions = {
      peadm::oid('peadm_role')               => $role,
      peadm::oid('peadm_availability_group') => $avail_group_letter,
    }
  }

  run_plan('peadm::subplans::prepare_agent', $component_target,
    primary_host           => $primary_target,
    dns_alt_names          => peadm::flatten_compact([$dns_alt_names]),
    certificate_extensions => $certificate_extensions,
  )

  # On component, run the puppet agent to finish initial configuring of component.
  # This run downloads the pe_repo package set from the primary; if the
  # primary's puppetserver restarts mid-download, the run fails with a 503
  # ("Attempted to borrow a JRubyInstance from the pool during a shutdown")
  # that nothing else retries. Retry a bounded number of times to ride out
  # that race; any other failure (a genuine catalog/resource error) is not
  # retried and surfaces on the first attempt.
  $component_runonce_max_attempts = 3
  $component_runonce_retry_delay = 30
  $component_runonce_result = range(1, $component_runonce_max_attempts).reduce(undef) |$memo, $attempt| {
    $prior_output = ($memo =~ NotUndef and !$memo.ok and $memo.error_set.first.value =~ Hash) ? {
      true    => $memo.error_set.first.value['_output'],
      default => undef,
    }
    $prior_is_transient = ($prior_output =~ String[1]) and ($prior_output =~ /Error 50\d on SERVER|Connection refused|Connection reset|end of file reached|Could not connect/)

    if $memo =~ NotUndef and ($memo.ok or !$prior_is_transient) {
      $memo
    } else {
      if $attempt > 1 {
        out::message("component's puppet_runonce hit a transient 503/connection error; retrying (attempt ${attempt}/${component_runonce_max_attempts}) after ${component_runonce_retry_delay}s...")
        ctrl::sleep($component_runonce_retry_delay)
      }
      run_task('peadm::puppet_runonce', $component_target, _catch_errors => true)
    }
  }

  unless $component_runonce_result.ok {
    $component_runonce_errors = $component_runonce_result.error_set.map |$result| {
      $result_value = $result.value
      $output = ($result_value =~ Hash) ? { true => $result_value['_output'], default => undef }
      $detail = ($output =~ String[1]) ? { true => $output, default => $result.error.message }
      "${result.target.name}: ${detail}"
    }.join("\n\n")
    fail_plan("peadm::puppet_runonce failed on ${component_target.peadm::certname()}: ${component_runonce_errors}")
  }

  return("Installation of component ${$component_target.peadm::certname()} with peadm_role: ${role} succeeded.")
}
