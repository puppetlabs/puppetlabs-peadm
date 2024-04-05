# @summary Produces a summarized hash of the given status data
# @param status_data Raw json data as returned by puppet infra status --format=json
# @param use_colors Adds colors to the status, defaults to true
# @return A simplified hash of of status data for the given stack
# @example Using function
#  peadm::determine_status($data, true)
#  {
#   "failed" => {
#             "activity/pe-std-replica.puppet.vm" => false,
#           "classifier/pe-std-replica.puppet.vm" => false,
#     "file-sync-client/pe-std-replica.puppet.vm" => false,
#               "master/pe-std-replica.puppet.vm" => false,
#             "puppetdb/pe-std-replica.puppet.vm" => false,
#                 "rbac/pe-std-replica.puppet.vm" => false
#   },
#   "passed" => {
#              "activity-service/pe-std.puppet.vm" => true,
#                "broker-service/pe-std.puppet.vm" => true,
#            "classifier-service/pe-std.puppet.vm" => true,
#          "code-manager-service/pe-std.puppet.vm" => true,
#      "file-sync-client-service/pe-std.puppet.vm" => true,
#     "file-sync-storage-service/pe-std.puppet.vm" => true,
#          "orchestrator-service/pe-std.puppet.vm" => true,
#                     "pe-master/pe-std.puppet.vm" => true,
#               "puppetdb-status/pe-std.puppet.vm" => true,
#                  "rbac-service/pe-std.puppet.vm" => true
#   },
#    "state" => {
#              "activity-service/pe-std.puppet.vm" => true,
#              "activity/pe-std-replica.puppet.vm" => false,
#                "broker-service/pe-std.puppet.vm" => true,
#            "classifier-service/pe-std.puppet.vm" => true,
#            "classifier/pe-std-replica.puppet.vm" => false,
#          "code-manager-service/pe-std.puppet.vm" => true,
#      "file-sync-client-service/pe-std.puppet.vm" => true,
#      "file-sync-client/pe-std-replica.puppet.vm" => false,
#     "file-sync-storage-service/pe-std.puppet.vm" => true,
#                "master/pe-std-replica.puppet.vm" => false,
#          "orchestrator-service/pe-std.puppet.vm" => true,
#                     "pe-master/pe-std.puppet.vm" => true,
#               "puppetdb-status/pe-std.puppet.vm" => true,
#              "puppetdb/pe-std-replica.puppet.vm" => false,
#                  "rbac-service/pe-std.puppet.vm" => true,
#                  "rbac/pe-std-replica.puppet.vm" => false
#   },
#   "status" => "\e[33mdegraded\e[0m"
# }
function peadm::determine_status(Array $status_data, Boolean $use_colors = true) >> Hash {
  # convert the data into a hash with the sevice names as the keys
  $hash_data = $status_data.reduce({}) | $res, $data | {
    stdlib::merge($res, { $data[service] => $data })
  }
  $out = $hash_data.reduce({}) | $res, $svc_data | {
    $service_name = $svc_data[0]
    $server = $svc_data[1][server]
    stdlib::merge($res, { "${service_name}/${server}" => $svc_data[1][state] == 'running' })
  }
  $bad_status = $out.filter | $item | { ! $item[1] }
  $passed_status = $out.filter | $item | { $item[1] }
  $overall_status = peadm::convert_status($bad_status.count, $out.count, $use_colors)
  return { status => $overall_status, state => $out, failed => $bad_status, passed => $passed_status }
}
