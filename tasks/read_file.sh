#!/bin/bash

main() {

	local python_exec=""

	if command -v python >/dev/null 2>&1; then
		python_exec=$(which python)
	elif command -v python2 >/dev/null 2>&1; then
		python_exec=$(which python2)
	elif command -v python3 >/dev/null 2>&1; then
		python_exec=$(which python3)
    else 
		echo "Error: No Python version 2 or 3 interpreter found." 2>&1
		exit 1
	fi

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