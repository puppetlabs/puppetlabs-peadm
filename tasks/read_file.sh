#!/bin/bash

main() {
	local python_exec=""

	# check if any python exec is available on the remote system. error out if not
	while :; do
		python_exec=$(command -v python)  && break
		python_exec=$(command -v python3) && break
		python_exec=$(command -v python2) && break
		python_exec=$(command -v /usr/libexec/platform-python) && break
		echo "Error: No Python version 2 or 3 interpreter found."
		exit 1
	done

	if [ -f "$PT_path" ] && [ -r "$PT_path" ]; then
		# The path is passed as an argument, never spliced into the Python
		# source, so quotes or other characters in it can't run as code.
		# Python prints the whole JSON result itself: on a read or decode
		# error it prints an _error object and exits 1, so stdout is never
		# partial JSON.
		"$python_exec" -c '
import io, json, sys
path = sys.argv[1]
try:
    with io.open(path, "r", encoding="utf-8", newline="") as f:
        print(json.dumps({"content": f.read()}))
except Exception as e:
    print(json.dumps({"_error": {
        "msg": "Could not read %s as UTF-8 text: %s" % (path, e),
        "kind": "peadm/read-file-error",
        "details": {"path": path},
    }}))
    sys.exit(1)
' "$PT_path"
	else
		cat <<-EOS
			{
				"content": null,
				"error": "File does not exist or is not readable"
			}
		EOS
	fi
}

main "$@"
