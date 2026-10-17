#!/bin/bash
# Debug only: print why the most recent puppet agent run on this host failed,
# plus memory state, so CI failures that Bolt summarizes as "exit code 4" can
# be attributed. Read-only; never fails.

state=/opt/puppetlabs/puppet/cache/state
report="${state}/last_run_report.yaml"

section() { printf '\n===== %s: %s\n' "$(hostname -f)" "$1"; }

section 'uptime / free -m'
uptime
free -m

section 'kernel OOM events'
dmesg -T 2>/dev/null | grep -iE 'out of memory|oom-kill|killed process' | tail -20

section 'last_run_summary.yaml'
cat "${state}/last_run_summary.yaml" 2>/dev/null

section 'last_run_report.yaml: failed resources and err-level logs'
if [ -f "$report" ]; then
  ls -l --time-style=full-iso "$report"
  /opt/puppetlabs/puppet/bin/ruby -rpuppet -rpuppet/transaction/report -e '
    r = YAML.unsafe_load_file(ARGV[0])
    puts "status=#{r.status} time=#{r.time} transaction_completed=#{r.transaction_completed}"
    r.resource_statuses.each_value { |s| puts "FAILED: #{s.resource}" if s.failed }
    r.logs.each { |l| puts "#{l.level}: #{l.source}: #{l.message}" if %i[err crit alert emerg].include?(l.level) }
  ' "$report" 2>&1 || grep -E -A6 'level: .*(err|crit|alert|emerg)' "$report" | head -300
else
  echo "no ${report}"
fi

for log in /var/log/puppetlabs/puppetserver/puppetserver.log \
           /var/log/puppetlabs/orchestration-services/orchestration-services.log \
           /var/log/puppetlabs/puppetdb/puppetdb.log \
           /var/log/puppetlabs/console-services/console-services.log; do
  [ -f "$log" ] || continue
  section "${log}: last 40 ERROR lines"
  grep -E ' ERROR ' "$log" | tail -40
done

section 'failed systemd units'
systemctl --failed --no-pager 2>/dev/null

exit 0
