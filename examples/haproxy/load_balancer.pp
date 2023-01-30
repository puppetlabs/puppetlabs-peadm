# @summary Example class for PE compiler load balancer
#
# This is a sample, not functional, demonstrating approximately what it would
# take to configure HA Proxy as a load balancer for Puppet Enterprise.
#
# lint:ignore:autoloader_layout
class examples::load_balancer {
  class { 'haproxy':
    global_options   => {
      'log'     => "${facts['facts[\'networking\'][\'ip\']']} local2",
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
      ],
    },
  }

  haproxy::listen { 'puppetserver':
    collect_exported => true,
    mode             => 'tcp',
    ipaddress        => $facts['networking']['ip'],
    ports            => '8140',
    options          => {
      option  => ['tcplog'],
      balance => 'leastconn',
    },
  }

  haproxy::listen { 'pcp-broker':
    collect_exported => true,
    mode             => 'tcp',
    ipaddress        => $facts['networking']['ip'],
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
    ipaddress        => $facts['networking']['ip'],
    ports            => '8081',
    options          => {},
  }
}
# lint:endignore
