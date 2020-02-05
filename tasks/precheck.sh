#!/bin/bash

hostname=$(hostname -f)
osfamily=$(cat /etc/os-release | grep -qi ubuntu && echo "ubuntu" || echo "el")
version=$(grep VERSION_ID /etc/os-release | cut -d '"' -f 2)
arch=$(uname -m)

# OS-specific modifications
[ "$osfamily" = "ubuntu" -a "$arch" = "x86_64" ] && arch="amd64"
[ "$osfamily" = "el" ] && version=$(echo "$version" | cut -d . -f 1)

# Output a JSON result for ease of Task usage in Puppet Task Plans
cat <<EOS
  {
    "hostname": "${hostname}",
    "platform": "${osfamily}-${version}-${arch}"
  }
EOS
