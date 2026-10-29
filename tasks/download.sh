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

# Describe a URL by the host and, for a tarball, its file name, so a pre-signed
# URL's query string and any user:password@ never reach the output, which Bolt
# logs (PE-47523). Anything that doesn't look like a plain host is left out.
describe-url() {
  local fallback='the source URL'
  # Keep in sync with peadm::url_file_name (the scheme and @ rules)
  local scheme='^[A-Za-z][A-Za-z0-9+.-]*://'
  # Without a scheme there's no telling where the host starts
  if ! [[ "$1" =~ $scheme ]]; then
    printf '%s' "$fallback"
    return
  fi

  local rest="${1#*://}"                 # drop scheme://
  local authority="${rest%%[/?#]*}"      # up to the path, query or fragment
  local after="${rest#"$authority"}"
  # An @ past the authority means user info holding a raw / ? or #, so where
  # it ends can't be told: print nothing of the URL.
  if [[ "$after" == *@* ]]; then
    printf '%s' "$fallback"
    return
  fi

  local host="${authority##*@}"          # drop user:password@
  local valid_host='^([[][0-9A-Fa-f:.]+[]]|[A-Za-z0-9.-]+)(:[0-9]+)?$'
  [[ "$host" =~ $valid_host ]] || host=''
  local path="${after%%[?#]*}"           # drop ?query and #fragment
  local name="${path##*/}"               # the last path segment
  # Only a tarball's name is safe to print: another last segment can be a
  # token. Keep in sync with peadm::url_tarball_name.
  local tarball_name='^[A-Za-z0-9][A-Za-z0-9._+-]*\.tar(\.gz)?$'
  [[ "$name" =~ $tarball_name ]] || name=''

  if [[ -n "$name" && -n "$host" ]]; then
    printf '%s from %s' "$name" "$host"
  elif [[ -n "$name" ]]; then
    printf '%s' "$name"
  elif [[ -n "$host" ]]; then
    printf '%s' "$host"
  else
    printf '%s' "$fallback"
  fi
}

# Download $1 to $2. $3 describes what is downloaded, for the output.
# TODO PE-47901: the URL is still on command lines (PT_source, curl's arguments) that sudo logs and ps shows.
download() {
  local description="${3:-$(describe-url "$1")}"
  printf '%s\n' "Downloading: ${description}"
  tmp_file=$(mktemp)
  echo "Downloading to temporary file ${tmp_file}"

  # curl's own output is discarded and only its exit status reported, as
  # defense in depth: -s already silences most of its error text, but some
  # versions and error paths may still print part of the URL (what follows the
  # first @ of a password, or the whole URL for one they can't parse). -g keeps
  # curl from globbing a URL with [ ] { } in it.
  if curl -s -g -f -L -o "${tmp_file}" "$1" >/dev/null 2>&1; then
    echo "Moving ${tmp_file} to target path ${2}"

    # Perform the move. If it doesn't work, clean up and return an error
    if ! mv "${tmp_file}" "$2"; then
      echo "Failed to move ${tmp_file} to ${2}! Deleting temporary file"
      rm "${tmp_file}"
      return 1
    fi
  else
    echo "Error: curl exited with $? downloading ${description} (see EXIT CODES in man curl)"
    echo "Removing temporary file ${tmp_file}"
    rm "${tmp_file}"
    return 1
  fi
}

download-size-verify() {
  local source="$1"
  local path="$2"

  # curl's stderr is dropped for the same reason as in download()
  urisize=$(curl -s -g -L --head "$source" 2>/dev/null | sed -rn 's/Content-Length: ([0-9]+)/\1/p' | tr -d '\012\015')
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
