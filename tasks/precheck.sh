#!/bin/bash

hostname=$(hostname -f)
osfamily=$(cat /etc/os-release | grep -qi ubuntu && echo "ubuntu" || echo "el")
version=$(grep VERSION_ID /etc/os-release | cut -d '"' -f 2)

# Output a JSON result for ease of Task usage in Puppet Task Plans
cat <<EOS
  {
    "hostname": "${hostname}",
    "platform": "${osfamily}-${version}"
  }
EOS
