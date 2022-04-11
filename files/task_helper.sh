#!/bin/bash
#=============================================================================
# Bash Task Helper
#
# This helper allows shell script authors to easily write Bolt tasks which
# return useful output, including success, failure, and key-value return data.
#
#   - Set your script shebang line to bash
#   - Source this script in the second line of your task
#   - For a task parameter "input", you may reference its value using ${input}
#   - Use `task-output "key" "value"` to set return data strings
#   - Use `task-succeed "message"`, or `task-fail "message"` to end the task
#   - The task helper reserves two file descriptors in order to manage and
#     process script output into valid task JSON. Consumers MUST NOT use or
#     redirect the reserved file descriptors 6 and 7.
#   - The task helper sets up a default EXIT trap. If consumers trap EXIT
#     themselves, they MUST call `task-exit` at the end of their trap to trigger
#     the helper's output finalization routine.
#   - When debugging, optionally call `task-verbose-output` before exiting. It
#     is recommended only to use this function call when debugging.
#
# Output:
#
# If the script exits with a non-zero exit code, or calls task-fail, all output
# will be returned to Bolt, including any keys set by `task-output`, and the
# message given to `task-fail` (if given).
#
# If the script exits successfully, or if task-succeed is called, no output
# will be returned except output specifically designated by the user via
# `task-output` and/or `task-succeed` function calls.
#
# Examples:
#
#   #!/bin/bash
#   source "$(dirname $0)/../../bash_task_helper/files/task_helper.sh"
#
#   echo "this output will be visible, but not set any key-value data"
#
#   VAR=$(date)
#   task-output "timestamp" "${VAR}"
#
#   task-succeed "demonstration task successful"
#
#=============================================================================


# Public: Set status=error, set a message, and exit the task
#
# This function ends the task. The task will return as failed. The function
# accepts an argument to set the task's return message, and an optional exit
# code to use.
#
# $1 - Message. A text string message to return in the task's `message` key.
# $2 - Exit code. A non-zero integer to use as the task's exit code.
#
# Examples
#
#   task-fail
#   task-fail "task failed because of reasons"
#   task-fail "task failed because of reasons" "127"
#
task-fail() {
  task-output "status" "error"
  _task_exit_string="$1"
  task-exit ${2:-1}
}

# DEPRECATED
fail() {
  task-output "_deprecation_warning" "WARN: bash_task_helper fail() is deprecated. Please use task-fail() instead."
  task-fail "$@"
}

# Public: Set status=success, set a message, and exit the task
#
# This function ends the task. The task will return as successful. The function
# accepts an argument to set the task's return message.
#
# $1 - Message. A text string message to return in the task's `message` key.
#
# Examples
#
#   task-succeed
#   task-succeed "task completed successfully"
#
task-succeed() {
  task-output "status" "success"
  _task_exit_string="$1"
  task-exit 0
}

# DEPRECATED
success() {
  task-output "_deprecation_warning" "WARN: bash_task_helper: use of success() is deprecated. Please use task-succeed() instead."
  task-succeed "$@"
}

# Public: Set a task output key to a string value
#
# Takes a key argument and a value argument, and ensures that upon task exit
# the key and value will be returned as part of the task output.
#
# $1 - Output key. Should contain only characters that match [A-Za-z0-9-_]
# $2 - Output value. Should be a string. Will be json-escaped.
#
# Examples
#
#   task-output "message" "an armadilo crossed the street"
#   task-output "maximum" "100"
#
task-output() {
  local key="${1}"
  local value=$(echo -n "$2" | task-json-escape)

  # Try to find an index for the key
  for i in "${!_task_output_keys[@]}"; do
    [[ "${_task_output_keys[$i]}" = "${key}" ]] && break
  done

  # If there's an index, set its value. Otherwise, add a new key
  if [[ "${_task_output_keys[$i]}" = "${key}" ]]; then
    _task_output_values[$i]="${value}"
  else
    _task_output_keys=("${_task_output_keys[@]}" "${key}")
    _task_output_values=("${_task_output_values[@]}" "${value}")
  fi
}

# Public: Set the task to always return full output
#
# Tasks normally do not return all output if the task returns successfully. If
# this function is invoked, the task will return all output regardless of exit
# code.
#
# $1 - true or false. Defaults to true. Pass false to turn verbose output off.
#
# Examples
#
#   task-verbose-output
#
task-verbose-output() {
  _task_verbose_output=${1:-true}
}

# Public: read text on stdin and output the text json-escaped
#
# A filter command which does its best to json-escape text input. Because the
# function is constrained to rely only on lowest-common-denominator posix
# utilities, it may not be able to fully escape all text on all platforms.
#
# Examples
#
#   printf "a string\nwith newlines\n" | task-json-escape
#   task-json-escape < file.txt
#
task-json-escape() {
  # This is imperfect, and will miss some characters. If we can figure out a
  # way to get iconv to catch more character types, we might improve that.
  # 1. Replace backslashes with escape sequences
  # 2. Replace unicode characters (if possible) with system iconv
  # 3. Replace other required characters with escape sequences
  #    Note that this includes two control-characters specifically
  # 4. Escape newlines (1/2): Replace all newlines with literal tabs
  # 5. Escape newlines (2/2): Replace all literal tabs with newline escape sequences
  # 6. Delete any remaining non-printable lines from the stream
  sed -e 's/\\/\\/g' \
    | { iconv -t ASCII --unicode-subst="\u%04x" || cat; } \
    | sed -e 's/"/\\"/g' \
          -e 's/\//\\\//g' \
          -e "s/$(printf '\b')/\\\b/g" \
          -e "s/$(printf '\f')/\\\f/g" \
          -e 's/\r/\\r/g' \
          -e 's/\t/\\t/g' \
          -e "s/$(printf "\x1b")/\\\u001b/g" \
          -e "s/$(printf "\x0f")/\\\u000f/g" \
    | tr '\n' '\t' \
    | sed 's/\t/\\n/g' \
    | tr -cd '\11\12\15\40-\176'
}

# Public: Print json task return data on task exit
#
# This function is called by a task helper EXIT trap. It will print json task
# return data on task termination.  The return data will include all output
# keys set using task-output, and all uncaptured stdout/stderr output produced
# by the script. This function should not be directly invoked, except inside a
# user-created EXIT trap.
#
# $1 - Exit code to terminate script with. Defaults to $?.
#
# Examples
#
#   task-exit
#   task-exit 1
#
task-exit() {
  # Record the exit code
  local exit_code=${1:-$?}
  local output

  # Unset the trap
  trap - EXIT

  # If appropriate, set an _output value. By default, if the task is
  # successful, full script output is suppressed. If the user passed a message
  # to task-succeed, that will still be returned as _output. If the task does
  # not exit successfully, or if the task is running in verbose mode, then full
  # output is returned (including a task-fail user message, if there is one)
  if [ "$exit_code" -ne 0 -o "$_task_verbose_output" = 'true' ]; then
    # Print the exit string, then set _output to everything that the script has printed
    echo -n "$_task_exit_string"
    task-output '_output' "$(cat "${_output_tmpfile}")"
  elif [ ! -z "$_task_exit_string" ]; then
    # Set _output to just the exit string
    task-output '_output' "${_task_exit_string}"
  fi

  # Reset outputs
  exec 1>&6
  exec 2>&7

  # Print JSON to stdout
  printf '{\n'
  for i in "${!_task_output_keys[@]}"; do
    # Print each key-value pair
    printf '  "%s": "%s"' "${_task_output_keys[$i]}" "${_task_output_values[$i]}"
    # Print a comma unless it's the last key-value
    [ ! "$(($i + 1))" -eq "${#_task_output_keys[@]}" ] && printf ','
    # Print a newline
    printf '\n'
  done
  printf '}\n'

  # Remove the output tempfile
  rm "$_output_tmpfile"

  # Resume an orderly exit
  exit "$exit_code"
}

# Test for colors. If unavailable, unset variables are ok
if tput colors &>/dev/null; then
  green="$(tput setaf 2)"
  red="$(tput setaf 1)"
  reset="$(tput sgr0)"
fi

# Use indirection to munge PT_ environment variables
# e.g. "$PT_version" becomes "$version"
for v in ${!PT_*}; do
  declare "${v#*PT_}"="${!v}"
done

# Set up variables to record task outputs
_task_output_keys=()
_task_output_values=()
_task_exit_string=''
_task_verbose_output=false

# Redirect all output (stdin, stderr) to a tempfile, and trap EXIT. Upon exit,
# print a Bolt task return JSON string, with the full contents of the tempfile
# in the "_output" key.
#
# Note: file descriptors 6 and 7 are used to save original stdout/stderr. These
#       were chosen as the file descriptors least likely to be used by shell
#       script task authors. Client scripts MUST NOT use these descriptors.
_output_tmpfile="$(mktemp)"
trap task-exit EXIT
exec 6>&1 \
     7>&2 \
     1>> "$_output_tmpfile" \
     2>&1
