# @summary Example class for PE PuppetDB load balancing
#
# lint:ignore:autoloader_layout
class examples::puppetdb {
  # TODO: split load balancing into two pools, A and B
  @@haproxy::balancermember { "${facts['clientcert']}_puppetdb_listener":
    listening_service => 'puppetdb',
    server_names      => $facts['networking']['fqdn'],
    ipaddresses       => $facts['networking']['ip'],
    ports             => '8081',
    options           => 'check',
  }
}
# lint:endignore
