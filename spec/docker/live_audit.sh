#!/usr/bin/env bash
src=$1
dst=$2
logfile=${2}/watcher.log
script_file=${0##*/}

#ps -af -ww |grep [l]ive_backup
while true
do
  while inotifywait --outfile=${logfile} -r -e modify,move,close_write,create $src
    do
      rsync -avz $src/ $dst
  done
done