class pe_xl::puppetdb_database {
  include pe_xl::agent
  include puppet_enterprise::params

  class { 'pe::postgres': }

  $pe_datadir = '/opt/puppetlabs/server/data'
  $pg_version = $puppet_enterprise::params::postgres_version

  $cm_query = 'nodes[certname] { resources { type = "Class" and title = "Pe_xl::Compiler" } }'
  $compilers = puppetdb_query($cm_query).map |$result| { $result['certname'] }

  $compilers.each |$cm| {
    puppet_enterprise::pg::ident_entry { "PuppetDB for ${cm}":
      client_certname    => $cm,
      user               => 'pe-puppetdb',
      ident_map_key      => 'pe-puppetdb-pe-puppetdb-map',
      pg_ident_conf_path => "${pe_datadir}/postgresql/${pg_version}/data/pg_ident.conf",
      database           => 'required-parameter-but-not-used',
    }
  }

}
