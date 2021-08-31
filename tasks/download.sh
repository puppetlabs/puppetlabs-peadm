#!/bin/bash

urisize=$(curl -s -L --head "$PT_source" | sed -n 's/Content-Length: \([0-9]\+\)/\1/p' | tr -d '\012\015')
filesize=$(stat -c%s "$PT_path" 2>/dev/null)

# Assume that if the file exists and is the same size, we don't have to
# re-download.
if [[ ! -z "$urisize" && ! -z "$filesize" && "$filesize" -eq "$urisize" ]]; then
  exit 0
else
  printf '%s\n' "Downloading: ${PT_source}" >&2
  curl -f -L -o "$PT_path" "$PT_source"
fi

if [[ "$PT_check_download" == "false" ]]; then
  exit 0
fi

if ! which -s gpg ; then
  echo "gpg binary required in path for checking download. Skipping check."
  exit 0
fi

echo "Importing Puppet gpg public key"
gpg --keyserver hkp://keyserver.ubuntu.com:11371 --recv-key 4528B6CD9E61EF26
if gpg --list-key --fingerprint 4528B6CD9E61EF26 | grep -q -E "D681 +1ED3 +ADEE +B844 +1AF5 +AA8F +4528 +B6CD +9E61 +EF26" ; then
  echo "gpg public key imported successfully."
else
  echo "Could not import gpg public key - wrong fingerprint."
  exit 1
fi

sigpath=${PT_path}.asc
sigsource=${PT_source}.asc

echo "Downloading tarball signature from ${sigsource}..."
curl -f -L -o "${sigpath}" "${sigsource}"
echo "Downloaded tarball signature to ${sigpath}."
echo "Checking tarball signature at ${sigpath}..."
if gpg --verify "${sigpath}" "${PT_path}" ; then
  echo "Signature verification succeeded."
else
  echo "Signature verification failed, please re-run the installation."
  exit 1
fi
