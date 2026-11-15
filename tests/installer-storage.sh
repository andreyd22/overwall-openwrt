#!/bin/sh
# Exercise storage admission against package-manager output, without host writes.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d /tmp/overwall-storage-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
sed -n '/^fail()/,/^# STORAGE_FUNCTIONS_END/p' "$root/scripts/install.sh" > "$work/functions"
. "$work/functions"
assert() { [ "$1" = "$2" ] || { printf 'FAIL: <%s> != <%s>\n' "$1" "$2"; exit 1; }; }
manager=opkg
printf '%s\n' 'Installing xray-core (25.1.30-r1) to root...' 'Installing luci-app-overwall (0.1.2-1) to root...' > "$work/plan"
assert "$(plan_packages "$work/plan")" "$(printf 'xray-core 25.1.30-r1\nluci-app-overwall 0.1.2-1')"
printf "%s\n" "Upgrading overwall-client on root from 0.1.0-1 to 0.1.2-1..." > "$work/plan"
assert "$(plan_packages "$work/plan")" "overwall-client 0.1.2-1"
manager=apk
printf '%s\n' '( 1/12) Installing xray-core (25.1.30-r1)' '(2/2) Upgrading overwall-client (0.1.0-r1 -> 0.1.2-r1)' > "$work/plan"
assert "$(plan_packages "$work/plan")" "$(printf 'xray-core 25.1.30-r1\noverwall-client 0.1.2-r1')"
cat > "$work/info" <<'INFO'
Package: xray-core
Version: old
Installed-Size: 100
Size: 100

Package: xray-core
Version: 25.1.30-r1
Installed-Size: 27627520
Size: 9841593
INFO
assert "$(opkg_sizes xray-core 25.1.30-r1 < "$work/info")" '26980 9611'
if opkg_sizes xray-core absent < "$work/info"; then echo 'FAIL missing version'; exit 1; fi
assert "$(printf 'xray-core installed size:\n26.3 MiB\n' | apk_size)" '27956'
if printf 'unknown\n' | apk_size; then echo 'FAIL unknown size'; exit 1; fi
# Model a router with 30 MiB persistent free, 64 MiB temporary free.
disk=/overlay
free_kib() { if [ "$1" = /overlay ]; then echo "${test_free:-30720}"; else echo "${test_tmp:-65536}"; fi; }
install_kib=1500; download_kib=1000
storage_check > "$work/result"
# Xray already present: 1.5 MiB dependencies fit even with only 10 MiB free.
test_free=10240
storage_check > "$work/result"
# Fresh Xray plus dependencies cannot fit a 10 MiB budget.
install_kib=29000; download_kib=11000
if (storage_check) > "$work/result" 2>&1; then echo 'FAIL admitted insufficient flash'; exit 1; fi
grep -q 'Не хватает' "$work/result"
# Also reject insufficient temporary RAM storage.
test_free=51200; test_tmp=1024
if (storage_check) > "$work/result" 2>&1; then echo 'FAIL admitted insufficient tmp'; exit 1; fi
grep -q 'Недостаточно временного места' "$work/result"
# Empty transaction is a safe repeat install with only the maintenance reserve.
test_free=30720; test_tmp=65536; install_kib=0; download_kib=0
storage_check > "$work/result"
echo 'PASS: plans, exact versions, sizes, existing Xray/30 MiB and 10 MiB, insufficient flash and tmp, repeat install'
