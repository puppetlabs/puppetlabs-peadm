#!/bin/bash

set -e

mkdir -p "$(dirname "$PT_path")"
touch "$PT_path"

if [ ! -z "$PT_owner" ]; then chown "$PT_owner" "$PT_path"; fi
if [ ! -z "$PT_group" ]; then chgrp "$PT_group" "$PT_path"; fi
if [ ! -z "$PT_mode"  ]; then chmod "$PT_mode"  "$PT_path"; fi

if [ ! -z "$PT_chown_r" ]; then
  chown -R "$PT_owner":"$PT_group" "$PT_chown_r"
fi

cat > "$PT_path" <<MKDIRPEOF
$PT_content
MKDIRPEOF

