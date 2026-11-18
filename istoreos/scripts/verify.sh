#!/bin/sh
# Read-only health check for the iStoreOS optimization baseline.
# It never writes config, never restarts services and never prints credentials.
# Usage: sh scripts/verify.sh ; exit code = number of failed checks.

fail=0

ok() {
	echo "PASS  $1"
}

bad() {
	echo "FAIL  $1"
	fail=$((fail + 1))
}

check_release() {
	rel=$(grep -m1 "DISTRIB_RELEASE" /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
	case "$rel" in
		25.12.*) ok "system release $rel" ;;
		*) bad "system release is '${rel:-unknown}', expected 25.12.x" ;;
	esac
}

check_overlay() {
	avail=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')
	if [ -n "$avail" ] && [ "$avail" -gt 10485760 ]; then
		ok "overlay available $((avail / 1024 / 1024))G"
	else
		bad "overlay available ${avail:-?}K, expected >10G"
	fi
}

check_data_mount() {
	if mount | grep -q " /mnt/data "; then
		ok "/mnt/data mounted"
	else
		bad "/mnt/data is not mounted (check fstab)"
	fi
}

check_passwall() {
	if apk list --installed 2>/dev/null | grep -q "luci-app-passwall"; then
		ok "luci-app-passwall installed"
	else
		bad "luci-app-passwall missing"
	fi
	if command -v xray >/dev/null 2>&1; then
		ok "xray-core present"
	else
		bad "xray binary missing"
	fi
	pgrep -f "xray run" >/dev/null 2>&1 && ok "xray running" || bad "xray not running"
	pgrep -f "chinadns-ng" >/dev/null 2>&1 && ok "chinadns-ng running" || bad "chinadns-ng not running"
}

check_dns() {
	cn=$(nslookup www.baidu.com 127.0.0.1 2>/dev/null | awk '/^Address: /{print $2}' | grep -E "^[0-9]+\\." | head -1)
	[ -n "$cn" ] && ok "domestic DNS resolves ($cn)" || bad "domestic DNS failed"
	foreign=$(nslookup chatgpt.com 127.0.0.1 2>/dev/null | awk '/^Address: /{print $2}' | head -1)
	[ -n "$foreign" ] && ok "proxy DNS resolves ($foreign)" || bad "proxy DNS failed"
}

check_http() {
	code=$(curl -s -o /dev/null -m 12 -w "%{http_code}" https://www.google.com/generate_204 2>/dev/null)
	[ "$code" = "204" ] || [ "$code" = "200" ] && ok "google reachable ($code)" || bad "google unreachable ($code)"
}

check_docker() {
	command -v docker >/dev/null 2>&1 || { bad "docker CLI missing"; return; }
	if docker ps --format "{{.Names}}" 2>/dev/null | grep -qx dpanel; then
		ok "dpanel running"
	else
		bad "dpanel not running"
	fi
	port=$(docker port dpanel 2>/dev/null | head -1)
	case "$port" in
		*192.168.100.1:8807*) ok "dpanel bound to LAN" ;;
		*) bad "dpanel binding unexpected: ${port:-none}" ;;
	esac
}

check_wan_rules() {
	leak=$(nft list chain inet fw4 input_wan 2>/dev/null | grep -E "8897|51819|1688|8807")
	if [ -z "$leak" ]; then
		ok "no sensitive WAN accept rules"
	else
		bad "sensitive WAN accept rules present"
	fi
}

check_release
check_overlay
check_data_mount
check_passwall
check_dns
check_http
check_docker
check_wan_rules

echo
if [ "$fail" -eq 0 ]; then
	echo "all checks passed"
	exit 0
fi
echo "$fail check(s) failed"
exit "$fail"
