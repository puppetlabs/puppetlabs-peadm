#!/opt/puppetlabs/bin/puppet apply

file { '/etc/puppetlabs/code-synchronized':
  ensure => directory,
  owner  => 'pe-puppet',
  group  => 'pe-puppet',
  mode   => '0750',
}

pe_hocon_setting { 'file-sync.repos.puppet-code.live-dir':
  path    => '/etc/puppetlabs/puppetserver/conf.d/file-sync.conf',
  setting => 'file-sync.repos.puppet-code.live-dir',
  value   => '/etc/puppetlabs/code-synchronized',
  require => File['/etc/puppetlabs/code-synchronized'],
  notify  => Service['pe-puppetserver'],
}

service { 'pe-puppetserver':
  ensure => running,
}
