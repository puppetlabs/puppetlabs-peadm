#!/bin/bash
# SCRATCH diagnostics (never merge). Run on the primary after add_replica.
PE=/opt/puppetlabs
H=$($PE/bin/puppet config print certname)
SSL=$($PE/bin/puppet config print ssldir)
echo "=== PE HA Replica group (rule/pinned) ==="
curl -sS --cert "$SSL/certs/$H.pem" --key "$SSL/private_keys/$H.pem" --cacert "$SSL/certs/ca.pem" \
  "https://$H:4433/classifier-api/v1/groups" \
| $PE/puppet/bin/ruby -rjson -e 'g=JSON.parse(STDIN.read); g.select{|x| x["name"]=~/HA Replica|Primary|Database/}.each{|x| puts x["name"]; puts "  rule=#{x["rule"].inspect}"}'
echo "=== infrastructure status / replicas ==="
$PE/bin/puppet infrastructure status 2>&1 | head -40
echo "=== provision_replica / reinitialize logs ==="
ls -t /var/log/puppetlabs/installer/ | head -30
for f in $(ls -t /var/log/puppetlabs/installer/provision_replica_*cli-output.log 2>/dev/null | head -2); do
  echo "--- $f (errors)"; grep -inE "error|fail|timeout|refused|denied" "$f" | head -40
  echo "--- $f (tail)"; tail -n 40 "$f"
done
for f in $(ls -t /var/log/puppetlabs/installer/*reinitialize_replica*.log 2>/dev/null | head -1); do
  echo "--- $f (errors)"; grep -inE "error|fail|could not|refused|denied|status" "$f" | head -60
done
exit 0
