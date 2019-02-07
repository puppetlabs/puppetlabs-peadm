# @summary Example class for PE compiler load balancing
#
class pe_xl::compiler {

  @@haproxy::balancermember { "${::clientcert}_puppetserver_listener":
    listening_service => 'puppetserver',
    server_names      => $::fqdn,
    ipaddresses       => $::ipaddress,
    ports             => '8140',
    options           => 'check',
  }

  @@haproxy::balancermember { "${::clientcert}_pcp-broker_listener":
    listening_service => 'pcp-broker',
    server_names      => $::fqdn,
    ipaddresses       => $::ipaddress,
    ports             => '8142',
    options           => 'check',
  }

}
