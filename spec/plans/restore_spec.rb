require 'spec_helper'

describe 'peadm::restore' do
  include BoltSpec::Plans
  
  backup_dir =  '/input/file'
  backup_tarball = "#{backup_dir}.tar.gz"

  let(:recovery_params) { 
    { 
      'targets'      => 'primary', 
      'input_file'   => backup_tarball,
      'restore_type' => 'recovery'
    }
  }
  let(:recovery_db_params) { 
    { 
      'targets'      => 'primary', 
      'input_file'   => backup_tarball,
      'restore_type' => 'recovery-db'
    } 
  }
  let(:classifier_only_params) { 
    { 
      'targets' => 'primary', 
      'input_file'   => backup_tarball,
      'restore_type' => 'custom', 
      'restore' => { 
        'activity'     => false,
        'ca'           => false,
        'classifier'   => true,
        'code'         => false,
        'config'       => false,
        'orchestrator' => false,
        'puppetdb'     => false,
        'rbac'         => false,
      } 
    } 
  }

  let(:cluster) { { 'params' => { 'primary_host' => 'primary', 'primary_postgresql_host' => 'postgres' } } }
  before(:each) do
    allow_apply

    expect_task('peadm::get_peadm_config').always_return(cluster)
    expect_out_message.with_params("cluster: " + cluster.to_s.gsub(/"/,'').gsub(/=>/,' => '))
    expect_out_message.with_params('# Restoring ldap secret key if it exists')
    expect_download("#{backup_dir}/peadm/peadm_config.json")
    allow_task('peadm::puppet_runonce')
  end

  it 'runs with recovery params' do
    expect_out_message.with_params('# Restoring database pe-puppetdb')
    expect_out_message.with_params('# Restoring ca, certs, code and config for recovery')

    expect_command("umask 0077   && cd /input   && tar -xzf /input/file.tar.gz\n")
    expect_command("/opt/puppetlabs/bin/puppet-backup restore   --scope=certs,code,config   --tempdir=/input/file   --force   /input/file/recovery/pe_backup-*tgz\n")
    expect_command("systemctl stop pe-console-services pe-nginx pxp-agent pe-puppetserver                pe-orchestration-services puppet pe-puppetdb\n")
    expect_command("test -f /input/file/rbac/keys.json   && cp -rp /input/file/keys.json /etc/puppetlabs/console-services/conf.d/secrets/   || echo secret ldap key doesn't exist\n")
    expect_command("su - pe-postgres -s /bin/bash -c   \"/opt/puppetlabs/server/bin/psql      --tuples-only      -d 'pe-puppetdb'      -c 'DROP SCHEMA IF EXISTS pglogical CASCADE;'\"\n").be_called_times(2)
    expect_command("su - pe-postgres -s /bin/bash -c   \"/opt/puppetlabs/server/bin/psql      -d 'pe-puppetdb'      -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'\"\n")
    expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'ALTER USER \\"pe-puppetdb\\" WITH SUPERUSER;\'"' + "\n")
    expect_command('/opt/puppetlabs/server/bin/pg_restore   -j 4   -d "sslmode=verify-ca       host=postgres       sslcert=/etc/puppetlabs/puppetdb/ssl/primary.cert.pem       sslkey=/etc/puppetlabs/puppetdb/ssl/primary.private_key.pem       sslrootcert=/etc/puppetlabs/puppet/ssl/certs/ca.pem       dbname=pe-puppetdb       user=pe-puppetdb"   -Fd /input/file/puppetdb/pe-puppetdb.dump.d' + "\n")
    expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'ALTER USER \\"pe-puppetdb\\" WITH NOSUPERUSER;\'"' + "\n")
    expect_command('su - pe-postgres -s /bin/bash -c   "/opt/puppetlabs/server/bin/psql      -d \'pe-puppetdb\'      -c \'DROP EXTENSION IF EXISTS pglogical CASCADE;\'"' + "\n")
    expect_command("/opt/puppetlabs/bin/puppet-infrastructure configure --no-recover\n")

    expect(run_plan('peadm::restore', recovery_params)).to be_ok
  end

  it 'runs with recovery-db params' do
    allow_any_command

    expect_out_message.with_params('# Restoring primary database for recovery')
    expect_out_message.with_params('# Restoring database pe-puppetdb')

    expect(run_plan('peadm::restore', recovery_db_params)).to be_ok
  end

  it 'runs with classifier-only params' do
    allow_any_command

    expect_task('peadm::restore_classification').with_params({
      "classification_file" => "#{backup_dir}/classifier/classification_backup.json"
    })

    expect(run_plan('peadm::restore', classifier_only_params)).to be_ok
  end

end
