#!/usr/bin/env bash
# must install inotify-tools from epel or self hosted repo
# live_audit.sh /watch_dir /tmp/backup
src=$1
dst=$2
logfile=${2}/watcher.log
script_file=${0##*/}
mkdir -p $dst
if [[ ! -d $src || ! -d $dst ]]; then
  echo "Source or destanation directory does not exist"
  exit 1
fi
#ps -af -ww |grep [l]ive_backup
while true
do
  while inotifywait --outfile=${logfile} -r -e modify,move,close_write,create $src
    do
      rsync -avz $src/ $dst
  done
done