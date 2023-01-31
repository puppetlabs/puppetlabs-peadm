# @summary Transforms a value in a human readable status with or without colors
# @param status A value of true, false, degraded, or an Integer that represents number of non operationally services
#        If using an integer, you must also supply the total amount of services 
# @param total the total number of services, used only when the status is an integer
# @param use_colors Adds colors to the status, defaults to true
# @return A status as a string with or without color
# @example With colors
#   peadm::convert_status(true) = "\e[32moperational\e[0m"
# @example Without colors
#   peadm::convert_status(true, 0, false) = "operational"
# @example Using integers where 1 of 2 services has failed
#   peadm::convert_status(1, 2, false) = "degraded"
# @example Using integers where 2 of 2 services has failed
#   peadm::convert_status(2, 2, false) = "failed"
# @example Using integers where 0 of 2 services has failed
#   peadm::convert_status(0, 2, false) = "operational"
function peadm::convert_status(
  Variant[String,Boolean, Integer] $status,
  Optional[Integer] $total = 0,
  Optional[Boolean] $use_colors = true
) >> String {
  if $status =~ Integer {
    if ( $status < 1 ) {
      $result = 'operational'
    } elsif $status == $total {
      $result = 'failed'
    } else {
      $result = 'degraded'
    }
  } else {
    $result = $status ? {
      true               => 'operational',
      false              => 'failed',
      /degraded/         => 'degraded',
      default            => 'unknown'
    }
  }
  if $use_colors {
    $color = $result ? {
      'degraded' => 'yellow',
      'failed'   => 'red',
      'operational' => 'green',
      default => 'yellow'
    }
    format::colorize($result, $color)
  } else {
    $result
  }
}
