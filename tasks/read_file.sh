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
		# The path goes in as an argument, never into the Python source, so
		# nothing in it can run as code. -E ignores PYTHON* variables, -s
		# skips the user site-packages directory, and the sys.path filter
		# drops the working directory, so none of them can change what runs.
		# Python prints the whole JSON result itself: any error while reading
		# prints an _error object and exits 1, so stdout is never partial JSON.
		"$python_exec" -E -s -c '
import sys
sys.path = [p for p in sys.path if p not in ("", ".")]
import io, json

def text(value):
    # Make a path or message safe for JSON when it holds bytes that are not
    # UTF-8: Python 2 gives byte strings, and Python 3 gives str with
    # surrogate escapes. Either way those bytes become U+FFFD.
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    try:
        value.encode("utf-8")
        return value
    except UnicodeEncodeError:
        return value.encode("utf-8", "surrogateescape").decode("utf-8", "replace")

path = sys.argv[1]
try:
    with io.open(path, "r", encoding="utf-8", newline="") as f:
        content = f.read()
except Exception as e:
    try:
        reason = text(str(e))
    except Exception:
        reason = repr(e)
    safe_path = text(path)
    print(json.dumps({"_error": {
        "msg": "Could not read %s: %s" % (safe_path, reason),
        "kind": "peadm/read-file-error",
        "details": {"path": safe_path},
    }}))
    sys.exit(1)
print(json.dumps({"content": content}))
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
