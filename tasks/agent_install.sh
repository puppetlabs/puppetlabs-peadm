#!/bin/bash

set -e

flags=$(echo $PT_install_flags | tr -d '[],\ "\ ')
curl -k "https://${PT_server}:8140/packages/current/install.bash" | bash -s -- $flags
