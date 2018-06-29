#!/bin/bash

urisize=$(curl -s --head "$PT_source" | sed -n -e 's/^M//' -e 's/Content-Length: \([0-9]\+\)/\1/p')
filesize=$(stat -c%s "$PT_path" 2>/dev/null)

# Assume that if the file exists and is the same size, we don't have to
# re-download.
if [ "$filesize" -ne "$urisize" ]; then
  curl -o "$PT_filename" "$PT_source"
else
  exit 0
fi
