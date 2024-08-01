#!/bin/bash
echo "Deleting certname ${PT_certname}"
read -r -d '' QUERY <<EOF
BEGIN TRANSACTION;
DO \$\$ DECLARE
    r RECORD;
    cname varchar;
BEGIN
  cname := '$PT_certname';
  RAISE NOTICE 'Deleting certname %', cname;

    FOR r IN (SELECT tablename FROM pg_tables 
      WHERE tablename LIKE 'resource_events_%') LOOP
        EXECUTE 'delete from ' || quote_ident(r.tablename) ||
        ' where certname_id in (select id from certnames where certname=\$1)' using 'cname';
    END LOOP;
    FOR r IN (SELECT tablename FROM pg_tables 
      WHERE tablename LIKE 'reports_%') LOOP
        EXECUTE 'delete from ' || quote_ident(r.tablename) || ' where certname=\$1' using 'cname';
    END LOOP;
    DELETE FROM catalog_inputs WHERE certname_id IN (SELECT id FROM certnames WHERE certname=cname);
    DELETE FROM certname_packages WHERE certname_id IN (SELECT id FROM certnames WHERE certname=cname);
    DELETE FROM certnames WHERE certname=cname;
END \$\$;
COMMIT TRANSACTION;
EOF

sudo -u pe-postgres -- /opt/puppetlabs/server/bin/psql pe-puppetdb -c "$QUERY"
