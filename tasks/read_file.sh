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

	local content error_field=''
	if [ -f "$PT_path" ] && [ -r "$PT_path" ]; then
		# The path goes in as an argument, not into the Python source. A failed
		# read fails the task (Python's traceback is the error) rather than
		# printing JSON Bolt can't parse, which callers took for a missing file.
		content=$("$python_exec" -c 'import io, json, sys; print(json.dumps(io.open(sys.argv[1], encoding="utf-8").read()))' "$PT_path") || exit 1
	else
		content=null
		error_field=', "error": "File does not exist or is not readable"'
	fi

	# With as_sensitive, the content goes under _sensitive, which Bolt wraps in
	# Sensitive and masks in bolt-debug.log and the task's result (PE-47523).
	# Bolt's --stream option still prints the task's raw output.
	if [ "$PT_as_sensitive" = "true" ]; then
		printf '%s\n' "{\"_sensitive\": {\"content\": ${content}}${error_field}}"
	else
		printf '%s\n' "{\"content\": ${content}${error_field}}"
	fi
}

main "$@"
