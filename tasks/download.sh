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

  # Perform the verification and return success or failure.
  if [ -z "$doc" ]; then
    # .asc file verification only
    #
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
    # Verification available and signature key is valid
    echo "Signature file verification successful"
    return 0
  else
    if gpg --verify "$sig" "$doc"; then
      echo "Signature verification succeeded"
      return 0
    else
      echo "Signature verification failed"
      return 1
    fi
  fi
}

download() {
  printf '%s\n' "Downloading: ${1}"
  tmp_file=$(mktemp)
  echo "Downloading to temporary file ${tmp_file}"

  if curl -s -f -L -o ${tmp_file} "$1"; then
    echo "Moving ${tmp_file} to target path ${2}"

    # Perform the move. If it doesn't work, clean up and return an error
    if ! mv "${tmp_file}" "$2"; then
      echo "Failed to move ${tmp_file} to ${2}! Deleting temporary file"
      rm "${tmp_file}"
      return 1
    fi
  else
    echo "Error: Curl has failed to download the file"
    echo "Removing temporary file ${tmp_file}"
    rm "${tmp_file}"
    return 1
  fi
}

download-size-verify() {
  local source="$1"
  local path="$2"

  urisize=$(curl -s -L --head "$source" | sed -rn 's/Content-Length: ([0-9]+)/\1/p' | tr -d '\012\015')
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

  # Try to download the signature file
  if ! download "${source}.asc" "${path}.asc" ; then
    if [[ "$PT_require_signature" == "true" ]]; then
      echo "Error: Signature required but ${source}.asc not available."
      exit 1
    else
      echo "Unable to download ${source}.asc. Skipping verification."
      download-size-verify "$source" "$path"
      return "$?"
    fi
  fi

  echo "Verifying signature file..."
  verify_output=$(verify-file "${path}.asc")
  verify_exit="$?"

  if [[ "$verify_exit" -eq "$EX_UNAVAILABLE" ]]; then
    if [[ "$PT_require_signature" == "true" ]]; then
      echo "Error: Key verification failed."
      exit 1
    fi
    echo "Verification unavailable. ${verify_output}. Skipping verification."
    download-size-verify "$source" "$path"
    return 0
  elif [[ "$verify_exit" -eq "0" ]]; then
    download "$source" "$path" || return 1
    echo "Verifying ${path}..."
    verify_output=$(verify-file "${path}.asc" "$path")
    verify_exit="$?"
    if [[ "$verify_exit" -eq "1" ]]; then
      echo "GPG check error: ${verify_output}"
      exit 1
    fi
    echo "GPG check result: ${verify_output}"
    return 0
  fi
}

if [[ "$PT_verify_download" == "true" ]]; then
  download-signature-verify "$PT_source" "$PT_path"
else
  download-size-verify "$PT_source" "$PT_path"
fi
