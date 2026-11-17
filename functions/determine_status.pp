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
  # convert the data into a hash keyed by "<service>/<server>". The same service name is
  # reported once per node (e.g. on both the primary and the replica), and a single node can
  # report a service name more than once (e.g. PCP Broker and PCP Broker v2), so a key is
  # only considered running if every entry for it is running.
  $out = $status_data.reduce({}) | $res, $data | {
    $key = "${data[service]}/${data[server]}"
    stdlib::merge($res, { $key => ($data[state] == 'running' and $res[$key] != false) })
  }
  $bad_status = $out.filter | $item | { ! $item[1] }
  $passed_status = $out.filter | $item | { $item[1] }
  # no services reported at all means nothing is running, not that everything is operational
  $overall_status = $out.empty ? {
    true    => peadm::convert_status(false, 0, $use_colors),
    default => peadm::convert_status($bad_status.count, $out.count, $use_colors),
  }
  return { status => $overall_status, state => $out, failed => $bad_status, passed => $passed_status }
}
