# @summary Example class for PE PuppetDB load balancing
#
class pe_xl::puppetdb {

  # TODO: split load balancing into two pools, A and B
  @@haproxy::balancermember { "${::clientcert}_puppetdb_listener":
    listening_service => 'puppetdb',
    server_names      => $::fqdn,
    ipaddresses       => $::ipaddress,
    ports             => '8081',
    options           => 'check',
  }

}
