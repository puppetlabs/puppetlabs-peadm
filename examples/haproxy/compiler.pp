# @summary Example class for PE compiler load balancing
#
# lint:ignore:autoloader_layout
class examples::compiler {
  @@haproxy::balancermember { "${facts['clientcert']}_puppetserver_listener":
    listening_service => 'puppetserver',
    server_names      => $facts['networking']['fqdn'],
    ipaddresses       => $facts['networking']['ip'],
    ports             => '8140',
    options           => 'check',
  }

  @@haproxy::balancermember { "${facts['clientcert']}_pcp-broker_listener":
    listening_service => 'pcp-broker',
    server_names      => $facts['networking']['fqdn'],
    ipaddresses       => $facts['networking']['ip'],
    ports             => '8142',
    options           => 'check',
  }
}
# lint:endignore
