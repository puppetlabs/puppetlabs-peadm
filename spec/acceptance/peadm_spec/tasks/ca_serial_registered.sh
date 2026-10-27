#!/bin/bash
# PE-47864: print {"table_present": <bool>, "count": <n>, "duplicates": <n>} for the pe-ca
# database's ca_signed_certificates table. count is the rows matching PT_certname and PT_serial;
# duplicates is the number of serials held by more than one row. table_present is false only when
# the query ran and found no pe-ca database or no ca_signed_certificates table (a filesystem-backed
# CA). A failing psql (sudo denied, postgres down, wrong host) aborts the task instead.
# shellcheck disable=SC2154  # PT_* are set by Bolt
set -eu
cd /

certname="${PT_certname}"
serial="${PT_serial}"
if [[ ! "${certname}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "certname contains characters outside [A-Za-z0-9._-]: ${certname}" >&2
  exit 1
fi
if [[ ! "${serial}" =~ ^[0-9]+$ ]]; then
  echo "serial is not a non-negative integer: ${serial}" >&2
  exit 1
fi

pe_psql() { sudo -u pe-postgres -- /opt/puppetlabs/server/bin/psql -tA "$@"; }

# Plain assignments, not command substitutions inside [[ ]], so set -e aborts on a psql failure.
db_present=$(pe_psql -d postgres -c "SELECT 1 FROM pg_database WHERE datname = 'pe-ca'")
if [[ "${db_present}" == "1" ]]; then
  table_present=$(pe_psql -d pe-ca -c "SELECT to_regclass('public.ca_signed_certificates') IS NOT NULL")
else
  table_present=f
fi

if [[ "${table_present}" != "t" ]]; then
  echo '{"table_present": false, "count": 0, "duplicates": 0}'
  exit 0
fi

count=$(pe_psql -d pe-ca -c "SELECT count(*) FROM ca_signed_certificates WHERE certname = \$\$${certname}\$\$ AND serial = ${serial}")
duplicates=$(pe_psql -d pe-ca -c "SELECT count(*) FROM (SELECT serial FROM ca_signed_certificates GROUP BY serial HAVING count(*) > 1) dup")
for n in "${count}" "${duplicates}"; do
  if [[ ! "${n}" =~ ^[0-9]+$ ]]; then
    echo "psql returned a non-numeric count: ${n}" >&2
    exit 1
  fi
done

printf '{"table_present": true, "count": %d, "duplicates": %d}\n' "${count}" "${duplicates}"
