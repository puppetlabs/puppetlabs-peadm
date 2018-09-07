plan pe_xl::upgrade::replica_set (
  String[1]           $version = '2018.1.2',
  String[1]           $console_password,
  Hash                $r10k_sources = { },

  String[1]           $primary_master_host,
  String[1]           $puppetdb_database_host,
  Array[String[1]]    $compile_master_hosts = [ ],
  Array[String[1]]    $dns_alt_names = [ ],

  Optional[String[1]] $primary_master_replica_host = undef,
  Optional[String[1]] $puppetdb_database_replica_host = undef,

  Optional[String[1]] $load_balancer_host = undef,
  Optional[String[1]] $token_file = undef,

  String[1]           $stagingdir = '/tmp',
  Optional[String[1]] $pe_tarball_location = "https://s3.amazonaws.com/pe-builds/released/${version}/puppet-enterprise-${version}-el-7-x86_64.tar.gz",
) {

  # set transport for primary_master_host to local
  $primary_master_host_local = [$primary_master_host].map |$n| { "local://${n}" }

  # Set variables and groups of nodes
  $all_hosts = [
    $primary_master_host_local,
    $puppetdb_database_host,
    $primary_master_replica_host,
    $puppetdb_database_replica_host,
    $compile_master_hosts,
    $load_balancer_host,
  ].pe_xl::flatten_compact()

  $front_hosts = [
    $compile_master_hosts,
    $load_balancer_host,
  ].pe_xl::flatten_compact()

  $primary_master_hosts = [
    $primary_master_host_local,
    $puppetdb_database_host,
  ].pe_xl::flatten_compact()
  
  $replica_master_hosts = [
    $primary_master_replica_host,
    $puppetdb_database_replica_host,
  ].pe_xl::flatten_compact()

  $dns_alt_names_csv = $dns_alt_names.reduce |$csv, $x| { "${csv},${x}" }

  # Get last name for dns_alt_names and assign to balancer
  if $compile_master_hosts and $dns_alt_names {
    $balancer = $dns_alt_names[-1]
  }

  # Download the PE tarball and send it to the nodes that need it
  $pe_tarball_name     = "puppet-enterprise-${version}-el-7-x86_64.tar.gz"
  $local_tarball_path  = "${stagingdir}/${pe_tarball_name}"
  $upload_tarball_path = "/tmp/${pe_tarball_name}"

  # Build replica enable command
  $enable_replica_cmd = 'env PATH=/opt/puppetlabs/bin:$PATH /opt/puppetlabs/bin/puppet infrastructure enable replica '
  if $token_file {
    $token_options = "--token-file=${token_file}"
  } else {
    $token_options =  ''
  }
  $enable_options_1 = "$token_options \
    --pcp-brokers=${primary_master_host}:8142 --agent-server-urls=${balancer}:8140 \
    --infra-agent-server-urls=${primary_master_host}:8140  \
    --infra-pcp-brokers=${primary_master_host}:8142 \
    --topology=mono-with-compile \
    --classifier-termini=${primary_master_host}:4433,${primary_master_replica_host}:4433 \
    --puppetdb-termini=${balancer}:8081,${primary_master_host}:8081,${primary_master_replica_host}:8081 \
    --skip-agent-config --yes "

  # Stop puppet on all hosts to be upgraded
    run_command('service puppet stop', $all_hosts)

  # Run the enable command to point all infrastecture at primary_master_host
  run_task(pe_xl::enable_replica, $primary_master_host_local,
    primary_master_replica => $primary_master_replica_host,
    command_options        => $enable_options_1,
  )

  # Run puppet to change any configs needed to point to primary_master_host
  $all_hosts.each |$host| {
    run_task('pe_xl::puppet_runonce', $host)
  }

  # Run puppet to change any configs needed to point to primary_master_host
  $all_hosts.each |$host| {
    run_task('pe_xl::puppet_runonce', $host)
  }

  # Get the primary master replica set upgrade done.
        # _catch_errors         => true,
  [$primary_master_replica_host,$puppetdb_database_replica_host].each |$host| {
    run_task('pe_xl::pe_install', $host,
      debug                 => true,
      tarball               => $upload_tarball_path,
      peconf                => '/tmp/pe.conf',
      shortcircuit_puppetdb => false,
    )
  }

  # Stop puppet on all hosts to be upgraded
  $replica_master_hosts.each |$host| {
    run_task('service', $host,
      name   => puppet,
      action => stop,
    )
  }

  # Run puppet to change any configs needed to point replica
  run_task('pe_xl::run_puppet_w_master', $primary_master_replica_host,
    puppet_master => $primary_master_replica_host,
  )
  run_task('pe_xl::run_puppet_w_master', $puppetdb_database_replica_host,
    puppet_master => $primary_master_replica_host,
  )
  run_task('pe_xl::run_puppet_w_master', $primary_master_replica_host,
    puppet_master => $primary_master_replica_host,
  )
  run_task('pe_xl::run_puppet_w_master', $puppetdb_database_replica_host,
    puppet_master => $primary_master_replica_host,
  )

#  $enable_options_on_replica = "$token_options \
#    --pcp-brokers=${primary_master_host}:8142 --agent-server-urls=${balancer}:8140 \
#    --infra-agent-server-urls=${primary_master_replica_host}:8140  \
#    --infra-pcp-brokers=${primary_master_host}:8142 \
#    --topology=mono-with-compile \
#    --classifier-termini=${primary_master_host}:4433,${primary_master_replica_host}:4433 \
#    --puppetdb-termini=${balancer}:8081${primary_master_replica_host}:8081 --yes "
#
#  # Run the enable command to point all infrastecture at primary_master_host
#  run_task(pe_xl::enable_replica, $primary_master_host_local,
#    primary_master_replica => $primary_master_replica_host,
#    command_options        => $enable_options_on_replica,
#  )
#
#  # Run puppet to change any configs needed to point replica
#  $replica_master_hosts.each |$host| {
#    run_task('pe_xl::run_puppet_w_master', $host,
#      puppet_master => $primary_master_replica_host,
#    )
#  }
#  # Run puppet to change any configs needed to point to primary_master_host
#  $front_hosts.each |$host| {
#    run_task('pe_xl::puppet_runonce', $host)
#  }

}
