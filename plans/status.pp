# @summary Aggregates the status of one or more stacks into a table format or 
#          json encoded string and dumps to stdout.
# @param targets These are a list of the primary puppetservers from one or multiple puppet stacks
# @param format The output format to dump to stdout (json or table)
# @param summarize Controls the type of json output to render, defaults to true
# @param verbose Toggles the output to show all the operationally services, can be loads more data
# @param colors Toggles the usage of colors, you may want to disable if the format is json
# @example 
#   peadm::status($targets, 'table', true, true)
plan peadm::status(
  TargetSpec $targets,
  Enum[json,table] $format = 'table',
  Boolean $verbose = false,
  Boolean $summarize = true,
  Boolean $colors = $format ? { json => false, default => true }
) {
  $results = run_task('peadm::infrastatus', $targets, { format => 'json'})
  # returns the data in a hash 
  $stack_status = $results.to_data.reduce({}) | $res, $item | {
    $data = $item[result][output] # parsed output of each target 
    $res.merge({ $item[target] => peadm::determine_status($data, $colors).merge(stack_name => $item[target] ) })
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
  $table_head = ['Stack', 'Status']
  $service_table_head = ['Stack', 'Service', 'Url', 'Status']

  $stack_table_rows = $stack_status.map | $item | { [$item[0], $item[1][status]] }
  $passed_table_rows = $overall_passed_stacks.map | $item | { [$item[0], $item[1][status]] }

  # produce array of degraded or failed services
  $bad_svc_rows = $overall_failed_stacks.merge($overall_degraded_stacks).map | $item | {
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
    $summary_table = format::table({title => $table_title,
                  head => $table_head,
                  rows => $stack_table_rows,
                  style => {width => 80}
                  })
    out::message($summary_table)
    unless $bad_svc_rows.empty {
      $failed_table = format::table({title => 'Failed Service Status',
                  head => $service_table_head,
                  rows => $bad_svc_rows[0]
                  })
      out::message($failed_table)
    }

    if $verbose and ! $good_svc_rows.empty {
      $passed_table = format::table({title => 'Operational Service Status',
                  head => $service_table_head,
                  rows => $good_svc_rows[0]
                  })
      out::message($passed_table)
    }
  } else {
    if $summarize {
      $failed = $bad_svc_rows.empty ? { true => [], default => peadm::convert_hash($service_table_head, $bad_svc_rows[0]) }
      $passed = $good_svc_rows.empty ? { true => [], default => peadm::convert_hash($service_table_head, $good_svc_rows[0]) }
      $summary_json = {
        'summary' => {
          'status' => $overall_status,
          'stacks' => $stack_table_rows.hash
        },
        'failed' => $failed,
        'operational' => $passed
      }
      return $summary_json
    } else {
      return $stack_status
    }
  }
}
