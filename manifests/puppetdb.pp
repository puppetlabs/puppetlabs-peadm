class pe_xl::puppetdb {
  include pe_xl::agent

  @@haproxy::balancermember { "${::clientcert}_puppetdb_listener":
    listening_service => 'puppetdb',
    server_names      => $::fqdn,
    ipaddresses       => $::ipaddress,
    ports             => '8081',
    options           => 'check',
  }

}
