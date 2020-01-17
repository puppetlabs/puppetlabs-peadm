#!/bin/bash

main() {
  cat "$PT_path"
}

outfile=$(mktemp)
main "$@" >"$outfile" 2>&1
exit_code=$?

cat <<EOS
  {
    "content": $(python -c "import json; print json.dumps(open('$outfile','r').read())")
  }
EOS

rm "$outfile"
exit $exit_code
