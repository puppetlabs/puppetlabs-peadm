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

	if [ -r "$PT_path" ]; then
		cat <<-EOS
			{
				"content": $($python_exec -c "import json; print(json.dumps(open('$PT_path','r').read()))")
			}
		EOS
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
