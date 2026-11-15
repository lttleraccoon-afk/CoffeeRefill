#!/bin/bash
set -eu

power_source() {
    /usr/bin/pmset -g batt | /usr/bin/awk -F "'" 'NR == 1 {print $2}'
}

if [[ "$(power_source)" != "AC Power" ]]; then
    printf '请先接电，再开始采样。\n' >&2
    exit 1
fi

log_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lid-feasibility.XXXXXX")
start=$(/bin/date '+%Y-%m-%d %H:%M:%S')
/usr/bin/pmset -g custom > "$log_dir/power-before.txt"
/usr/bin/caffeinate -is -t 180 &
assertion_pid=$!

cleanup() {
    kill "$assertion_pid" 2>/dev/null || true
    wait "$assertion_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

own_assertions() {
    /usr/bin/pmset -g assertions |
        /usr/bin/awk -v owner="pid $assertion_pid(caffeinate)" 'index($0, owner)'
}

/bin/sleep 1
own_assertions > "$log_dir/assertions-on.txt"
/usr/bin/grep -q PreventUserIdleSystemSleep "$log_dir/assertions-on.txt"
/usr/bin/grep -q PreventSystemSleep "$log_dir/assertions-on.txt"

printf '日志目录 %s\n' "$log_dir"
printf '接电合盖 20 秒再开盖。然后拔电，等 5 秒，再合盖 20 秒并打开。\n'
printf '约 3 分钟后自动结束。合盖时请将 Mac 放在通风桌面。\n'
printf 'epoch\tlocal_time\tpower_source\tlid_closed\tlid_causes_sleep\n' > "$log_dir/samples.tsv"
deadline=$(( $(/bin/date +%s) + 170 ))
while (( $(/bin/date +%s) < deadline )); do
    stamp=$(/bin/date '+%s	%Y-%m-%d %H:%M:%S')
    power=$(power_source)
    lid=$(/usr/sbin/ioreg -r -k AppleClamshellState -d 1 |
        /usr/bin/awk '/"AppleClamshellState"/ {closed=$NF} /"AppleClamshellCausesSleep"/ {policy=$NF} END {printf "%s\t%s", closed, policy}')
    printf '%s\t%s\t%s\n' "$stamp" "$power" "$lid" >> "$log_dir/samples.tsv"
    /bin/sleep 1
done

cleanup
trap - EXIT
own_assertions > "$log_dir/assertions-off.txt"
test ! -s "$log_dir/assertions-off.txt"
/usr/bin/pmset -g custom > "$log_dir/power-after.txt"
/usr/bin/pmset -g log | /usr/bin/awk -v start="$start" '
    substr($0, 1, 19) >= start && /^[0-9][0-9][0-9][0-9]-/ &&
    /Entering Sleep state|Entering DarkWake state|Wake from|Clamshell Sleep/ { print }
' > "$log_dir/sleep-events.txt"
if /usr/bin/cmp -s "$log_dir/power-before.txt" "$log_dir/power-after.txt"; then
    printf '断言已释放，前后电源配置一致。\n'
else
    printf '采样期间电源配置发生变化，请检查前后快照。\n' >&2
    exit 1
fi
