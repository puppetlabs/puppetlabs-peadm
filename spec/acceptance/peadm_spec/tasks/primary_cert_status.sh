#!/bin/bash
# PE-47864: print {"serial": <decimal>, "in_crl": <bool>} for the host certificate of PT_certname.
# The serial is read from the file puppet presents, not from the CA, because after a restore the
# file is the only record of the serial the regenerated certificate was actually given.
# shellcheck disable=SC2154  # PT_* are set by Bolt
set -eu
cd /

certname="${PT_certname}"
if [[ ! "${certname}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "certname contains characters outside [A-Za-z0-9._-]: ${certname}" >&2
  exit 1
fi

ssldir=/etc/puppetlabs/puppet/ssl
raw=$(/opt/puppetlabs/puppet/bin/openssl x509 -serial -noout -in "${ssldir}/certs/${certname}.pem")
hex=${raw#serial=}
if [[ ! "${hex}" =~ ^[0-9A-Fa-f]+$ ]]; then
  echo "could not parse a serial from: ${raw}" >&2
  exit 1
fi

# The decimal conversion below is 64-bit signed bash arithmetic. More than 15 significant hex
# digits is refused rather than risk a wrong number: 15 digits fit in 60 bits, and a 16th could
# exceed the signed 63-bit range.
significant=${hex#"${hex%%[!0]*}"}
if (( ${#significant} > 15 )); then
  echo "serial ${hex} is too wide to report as a decimal integer" >&2
  exit 1
fi

# The CRL's "Serial Number:" lines are bare uppercase hex of even length (e.g. 0FDB).
hex=$(printf '%s' "${hex}" | tr '[:lower:]' '[:upper:]')
if (( ${#hex} % 2 == 1 )); then hex="0${hex}"; fi

if [[ ! -r "${ssldir}/ca/ca_crl.pem" ]]; then
  echo "no CRL at ${ssldir}/ca/ca_crl.pem: is this host the primary CA?" >&2
  exit 1
fi
crl=$(/opt/puppetlabs/puppet/bin/openssl crl -text -noout -in "${ssldir}/ca/ca_crl.pem")
if grep -Eq "Serial Number:[[:space:]]+${hex}[[:space:]]*\$" <<<"${crl}"; then in_crl=true; else in_crl=false; fi

printf '{"serial": %d, "in_crl": %s}\n' "$((16#${hex}))" "${in_crl}"
