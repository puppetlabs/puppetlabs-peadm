#!/opt/puppetlabs/bin/puppet apply 
function param($name) { inline_template("<%= ENV['PT_${name}'] %>") }

class configure_pdb_pg_ident_entry (
  String[1] $certname = param('certname'),
) {
  include puppet_enterprise::params

  $pe_datadir = '/opt/puppetlabs/server/data'
  $pg_version = $puppet_enterprise::params::postgres_version

  puppet_enterprise::pg::ident_entry { "PuppetDB for ${certname}":
    client_certname    => $certname,
    user               => 'pe-puppetdb',
    ident_map_key      => 'pe-puppetdb-pe-puppetdb-map',
    pg_ident_conf_path => "${pe_datadir}/postgresql/${pg_version}/data/pg_ident.conf",
    database           => 'required-parameter-but-not-used',
  }

}

include configure_pdb_pg_ident_entry
