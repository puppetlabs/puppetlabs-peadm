#!/bin/bash

hostname=$(hostname -f)
osfamily=$(cat /etc/os-release | grep -qi ubuntu && echo "ubuntu" || echo "el")
version=$(grep VERSION_ID /etc/os-release | cut -d '"' -f 2)
arch=$(uname -m)

# Because 64-bit Ubuntu wanted to be special.
[ "$osfamily" = "ubuntu" -a "$arch" = "x86_64" ] && arch="amd64"

# Output a JSON result for ease of Task usage in Puppet Task Plans
cat <<EOS
  {
    "hostname": "${hostname}",
    "platform": "${osfamily}-${version}-${arch}"
  }
EOS
