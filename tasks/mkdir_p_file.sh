#!/bin/bash

set -e

# Needs a Python interpreter on the target, as read_file does.
#
# Parameters arrive as JSON on stdin. With environment input, Bolt puts them
# on the remote command line (`env PT_content=...`), where sudo logs them, ps
# shows them and Bolt's trace log records them, and the content is often a
# secret (PE-47523).
params=$(cat)

python_exec=$(command -v python || command -v python3 || command -v python2 || command -v /usr/libexec/platform-python) || {
  echo "Error: No Python version 2 or 3 interpreter found."
  exit 1
}

# Print a parameter's value, or nothing if it's unset or null. It goes through
# a pipe, never as an argument.
param() {
  printf '%s' "$params" | "$python_exec" -c '
import json, sys
# Bytes in and out, as UTF-8 whatever the locale (Python 2 has no .buffer)
stdin = getattr(sys.stdin, "buffer", sys.stdin)
stdout = getattr(sys.stdout, "buffer", sys.stdout)
value = json.loads(stdin.read().decode("utf-8")).get(sys.argv[1])
stdout.write(("" if value is None else value).encode("utf-8"))
' "$1"
}

path=$(param path)
owner=$(param owner)
group=$(param group)
mode=$(param mode)
chown_r=$(param chown_r)

mkdir -p "$(dirname "$path")"
touch "$path"

if [ -n "$owner" ]; then chown "$owner" "$path"; fi
if [ -n "$group" ]; then chgrp "$group" "$path"; fi
if [ -n "$mode"  ]; then chmod "$mode"  "$path"; fi

if [ -n "$chown_r" ]; then
  chown -R "$owner":"$group" "$chown_r"
fi

{ param content; echo; } > "$path"
