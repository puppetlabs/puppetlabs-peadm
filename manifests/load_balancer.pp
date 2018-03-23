class pe_xl::load_balancer {
  include pe_xl::agent

  class { 'haproxy':
    global_options   => {
      'log'     => "${::ipaddress} local2",
      'chroot'  => '/var/lib/haproxy',
      'pidfile' => '/var/run/haproxy.pid',
      'maxconn' => 5000,
      'user'    => 'haproxy',
      'group'   => 'haproxy',
      'daemon'  => '',
      'stats'   => 'socket /var/lib/haproxy/stats',
    },
    defaults_options => {
      'timeout' => [
        'http-request 120s',
        'queue 1m',
        'connect 10s',
        'client 2m',
        'server 2m',
      ]
    }
  } 

  haproxy::listen { 'puppetserver':
    collect_exported => true,
    mode             => 'tcp',
    ipaddress        => $::ipaddress,
    ports            => '8140',
    options          => {
      option  => ['tcplog'],
      balance => 'leastconn',
    },
  }

  haproxy::listen { 'pcp-broker':
    collect_exported => true,
    mode             => 'tcp',
    ipaddress        => $::ipaddress,
    ports            => '8142',
    options          => {
      option  => ['tcplog'],
      balance => 'leastconn',
    },
  }

  haproxy::listen { 'puppetdb':
    collect_exported => true,
    ipaddress        => $::ipaddress,
    ports            => '8081',
    options          => {},
  }

}
