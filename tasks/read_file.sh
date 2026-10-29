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
	if [ -r "$PT_path" ]; then
		content=$($python_exec -c "import json; print(json.dumps(open('$PT_path','r').read()))")
	else
		content=null
		error_field=', "error": "File does not exist or is not readable"'
	fi

	# With as_sensitive, the content goes under _sensitive, which Bolt wraps in
	# Sensitive and masks in its logs and output (PE-47523).
	if [ "$PT_as_sensitive" = "true" ]; then
		printf '%s\n' "{\"_sensitive\": {\"content\": ${content}}${error_field}}"
	else
		printf '%s\n' "{\"content\": ${content}${error_field}}"
	fi
}

main "$@"
