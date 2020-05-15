#!/bin/bash

main() {
	if [ -r "$PT_path" ]; then
		cat <<-EOS
			{
				"content": $(python_cmd -c "import json; print json.dumps(open('$PT_path','r').read())")
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

python_cmd() {
	if command -v python >/dev/null 2>&1; then
		python "$@"
	else
		python3 "$@"
	fi
}

main "$@"
exit_code=$?
exit $exit_code
