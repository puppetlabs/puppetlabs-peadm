#!/bin/bash

urisize=$(curl -s -L --head "$PT_source" | sed -n 's/Content-Length: \([0-9]\+\)/\1/p' | tr -d '\012\015')
filesize=$(stat -c%s "$PT_path" 2>/dev/null)

# Assume that if the file exists and is the same size, we don't have to
# re-download.
if [[ ! -z "$urisize" && "${urisize}x" != 'x' && ! -z "$filesize" && "$filesize" -eq "$urisize" ]]; then
#  exit 0
  echo "URLSIZE: $urisize, FILESIZE: $filesize" 2>&1
else
  echo  "PATH: $PT_path SOURCE: $PT_source" 2>&1
  curl -L -o "$PT_path" "$PT_source"
fi

