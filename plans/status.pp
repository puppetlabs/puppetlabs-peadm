# @summary Return status information from one or more PE clusters in a table format
#
# @param targets These are a list of the primary puppetservers from one or multiple puppet stacks
# @param format The output format to dump to stdout (json or table)
# @param summarize Controls the type of json output to render, defaults to true
# @param verbose Toggles the output to show all the operationally services, can be loads more data
# @param colors Toggles the usage of colors, you may want to disable if the format is json
# @example Using plan
#   peadm::status($targets, 'table', true, true)
plan peadm::status(
  TargetSpec $targets,
  Enum[json,table] $format = 'table',
  Boolean $verbose = false,
  Boolean $summarize = true,
  Boolean $colors = $format ? { 'json' => false, default => true }
) {
  peadm::assert_supported_bolt_version()

  $results = run_task('peadm::infrastatus', $targets, { format => 'json' })
  # returns the data in a hash
  $stack_status = $results.reduce({}) | $res, $item | {
    $data = $item.value[output]
    $stack_name = $item.target.peadm::certname()
    $status = stdlib::merge(peadm::determine_status($data, $colors), { stack_name => $stack_name })
    stdlib::merge($res, { $stack_name => $status })
  }

  $overall_degraded_stacks = $stack_status.filter | $item | { $item[1][status] =~ /degraded/ }
  $overall_failed_stacks = $stack_status.filter | $item | { $item[1][status] =~ /failed/ }
  $overall_passed_stacks = $stack_status.filter | $item | { $item[1][status] =~ /operational/ }

  # determine if the overall status is failed, operationally, or degraded
  if $overall_degraded_stacks.count > 0 {
    $overall_status = peadm::convert_status('degraded', undef, $colors)
  } else {
    $overall_status = peadm::convert_status($overall_failed_stacks.count, $stack_status.count, $colors)
  }

  # produce titles and headers for tables
  $table_title = "Overall Status: ${overall_status}"
  $table_head = ['Cluster', 'Status']
  $service_table_head = ['Cluster', 'Service', 'Url', 'Status']

  $stack_table_rows = $stack_status.map | $item | { [$item[0], $item[1][status]] }
  $passed_table_rows = $overall_passed_stacks.map | $item | { [$item[0], $item[1][status]] }

  # produce array of degraded or failed services
  $bad_svc_rows = stdlib::merge($overall_failed_stacks, $overall_degraded_stacks).map | $item | {
    $item[1][failed].map | $svc | {
      [$item[0], *$svc[0].split('/'), peadm::convert_status($svc[1], undef, $colors)]
    }
  }

  # produce array of working services
  $good_svc_rows = $stack_status.map | $item | {
    $item[1][passed].map | $svc | {
      [$item[0], *$svc[0].split('/'), peadm::convert_status($svc[1], undef, $colors)]
    }
  }

  # print to table via out::message or return json output
  if $format == 'table' {
    # Summary table
    out::message(
      format::table({
          title => $table_title,
          head  => $table_head,
    rows  => $stack_table_rows }))

    # Failed services table
    unless $bad_svc_rows.empty {
      out::message(
        format::table({
            title => 'Failed Service Status',
            head  => $service_table_head,
      rows  => $bad_svc_rows.reduce([]) |$memo,$rows| { $memo + $rows } }))
    }

    # Operational services table
    if $verbose and ! $good_svc_rows.empty {
      out::message(
        format::table({
            title => 'Operational Service Status',
            head  => $service_table_head,
      rows  => $good_svc_rows.reduce([]) |$memo,$rows| { $memo + $rows } }))
    }
  } else {
    if $summarize {
      $failed = $bad_svc_rows.empty ? { true => [], default => peadm::convert_hash($service_table_head, $bad_svc_rows[0]) }
      $passed = $good_svc_rows.empty ? { true => [], default => peadm::convert_hash($service_table_head, $good_svc_rows[0]) }
      $summary_json = {
        'summary' => {
          'status' => $overall_status,
          'stacks' => Hash($stack_table_rows),
        },
        'failed' => $failed,
        'operational' => $passed,
      }
      return $summary_json
    } else {
      return $stack_status
    }
  }
}
