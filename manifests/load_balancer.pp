# @summary Example class for PE compiler load balancer
#
class pe_xl::load_balancer {

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
        'connect 10s',
        'queue 1m',
        'client 2m',
        'server 2m',
        'http-request 120s',
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
      timeout => [
        'tunnel 15m',
        'client-fin 30s',
      ],
    },
  }

  # TODO: split load balancing into two pools, A and B
  haproxy::listen { 'puppetdb':
    collect_exported => true,
    ipaddress        => $::ipaddress,
    ports            => '8081',
    options          => {},
  }

}
