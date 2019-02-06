function pe_xl::print_apply_result(
  Variant[ApplyResult, ResultSet] $result,
) {
  $enumerable = $result ? {
    ResultSet => $result,
    default   => [$result],
  }

  $enumerable.each |ApplyResult $apply| {
    $apply.report['logs'].each |$log| {
      # TODO: include file and line number, if present
      notice("${log['time']} ${log['level'].upcase} ${log['source']} ${log['message']}")
    }

    $status = $apply.report['status']
    $message = $apply.message
    $target = $apply.target.name
    notice("\"${status}\" on ${target}: ${message}")
  }
}
