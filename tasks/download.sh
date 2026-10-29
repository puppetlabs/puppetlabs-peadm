#!/bin/bash

# Exit code indicating "a service is unavailable", from
# /usr/include/sysexits.h. The verify-file function will return this code if
# prerequisites for verification are unavailable.
EX_UNAVAILABLE=69

verify-file() {
  local sig="$1"
  local doc="$2"
  local keyid

  # The GPG binary is required to be present in order to perform file download
  # verification. If it is not present, return EX_UNAVAILABLE.
  if ! command -v gpg >/dev/null; then
    echo "gpg binary not found; required in path for checking download"
    return "$EX_UNAVAILABLE"
  fi

  # The verification key must be present, or it must be possible to download it
  # from the keyserver to perform file verification. If it is not present,
  # return EX_UNAVAILABLE.
  keyid=$(gpg --list-packets --with-colons "$sig" | awk '/:signature packet:/{print $NF; exit 0}')
  if [[ -z "$keyid" ]]; then
    echo "Unable to determine verification key from ${sig}"
    return "$EX_UNAVAILABLE"
  elif ! { gpg --list-keys "$keyid" || gpg --keyserver "$PT_key_server" --recv-key "$keyid"; } then
    echo "Unable to download verification key ${keyid}"
    return "$EX_UNAVAILABLE"
  fi

  # Perform the verification and return success or failure.
  if gpg --verify "$sig" "$doc"; then
    echo "Signature verification succeeded"
    return 0
  else
    echo "Signature verification failed"
    return 1
  fi
}

# Describe a URL by its file name and host only, so a pre-signed URL's query
# string and any user:password@ never reach the output, which Bolt logs
# (PE-47523). Anything that doesn't look like a plain host is left out.
describe-url() {
  local rest="${1#*://}"                 # drop scheme://
  local authority="${rest%%[/?#]*}"      # up to the path, query or fragment
  local after="${rest#"$authority"}"
  # An @ past the authority means user info holding a raw / ? or #, so where
  # it ends can't be told: print nothing of the URL.
  if [[ "$after" == *@* ]]; then
    printf 'the source URL'
    return
  fi

  local host="${authority##*@}"          # drop user:password@
  local valid_host='^([[][0-9A-Fa-f:.]+[]]|[A-Za-z0-9.-]+)(:[0-9]+)?$'
  [[ "$host" =~ $valid_host ]] || host=''
  local path="${after%%[?#]*}"           # drop ?query and #fragment
  local name="${path##*/}"               # the last path segment
  # Only a tarball's name is safe to print: another last segment can be a token
  [[ "$name" =~ \.tar(\.gz)?$ ]] || name=''

  if [[ -n "$name" && -n "$host" ]]; then
    printf '%s from %s' "$name" "$host"
  elif [[ -n "$name" ]]; then
    printf '%s' "$name"
  elif [[ -n "$host" ]]; then
    printf '%s' "$host"
  else
    printf 'the source URL'
  fi
}

# Download $1 to $2. $3 describes what is downloaded, for the output.
# TODO PE-47901: the URL is still on command lines (PT_source, curl's arguments) that sudo logs and ps shows.
download() {
  local description="${3:-$(describe-url "$1")}"
  local curl_error
  printf '%s\n' "Downloading: ${description}"
  tmp_file=$(mktemp)
  echo "Downloading to temporary file ${tmp_file}"

  # curl's error goes to stdout with the rest: Bolt drops a task's stderr when
  # there's stdout. -g keeps curl from globbing a URL with [ ] { } in it. In
  # practice curl's first line names a host at most, but some errors (a bad
  # URL) print the URL, on that line or the next, so only the first line
  # is kept, with any URL in it replaced.
  if curl_error=$(curl -sS -g -f -L -o "${tmp_file}" "$1" 2>&1); then
    echo "Moving ${tmp_file} to target path ${2}"

    # Perform the move. If it doesn't work, clean up and return an error
    if ! mv "${tmp_file}" "$2"; then
      echo "Failed to move ${tmp_file} to ${2}! Deleting temporary file"
      rm "${tmp_file}"
      return 1
    fi
  else
    local curl_status=$?
    curl_error="${curl_error%%$'\n'*}"
    curl_error="${curl_error//"$1"/<url>}"
    echo "Error: curl exited with ${curl_status} downloading ${description}${curl_error:+: ${curl_error}}"
    echo "Removing temporary file ${tmp_file}"
    rm "${tmp_file}"
    return 1
  fi
}

download-size-verify() {
  local source="$1"
  local path="$2"

  urisize=$(curl -s -g -L --head "$source" | sed -rn 's/Content-Length: ([0-9]+)/\1/p' | tr -d '\012\015')
  filesize=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null)

  echo "Filesize: ${filesize}"
  echo "Content-Length header: ${urisize}"

  # Assume that if the file exists and is the same size, we don't have to
  # re-download.
  if [[ ! -z "$urisize" && ! -z "$filesize" && "$filesize" -eq "$urisize" ]]; then
    echo "File size matches HTTP Content-Length header. Using file as-is."
    exit 0
  else
    download "$source" "$path"
  fi
}

download-signature-verify() {
  local source="$1"
  local path="$2"

  local signature
  signature="the .asc signature for $(describe-url "$source")"
  if ! download "${source}.asc" "${path}.asc" "$signature"; then
    echo "Unable to download ${signature}. Skipping verification."
    download-size-verify "$source" "$path"
    return "$?"
  fi

  echo "Verifying ${path}..."
  verify_output=$(verify-file "${path}.asc" "$path");
  verify_exit="$?"
  if [[ "$verify_exit" -eq "$EX_UNAVAILABLE" ]]; then
    echo "Verification unavailable. ${verify_output}. Skipping verification."
    download-size-verify "$source" "$path"
  elif [[ "$verify_exit" -eq "1" ]]; then
    echo "$verify_output"
    download "$source" "$path" || return 1
    echo "Verifying ${path}..."
    verify-file "${path}.asc" "$path"
  fi
}

if [[ "$PT_verify_download" == "true" ]]; then
  download-signature-verify "$PT_source" "$PT_path"
else
  download-size-verify "$PT_source" "$PT_path"
fi
