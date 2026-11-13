#!/bin/sh
# Overwall VPN installer 0.1.0. HTTPS + signed package repositories.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Запустите от root.' >&2; exit 1; }
[ -r /etc/openwrt_release ] || { echo 'Нужен OpenWrt.' >&2; exit 1; }
. /etc/openwrt_release
case "$DISTRIB_RELEASE" in
 25.12.*) manager=apk; series=25.12 ;;
 24.10.*) manager=opkg; series=24.10 ;;
 *) echo 'Поддерживаются стабильные OpenWrt 25.12.x и 24.10.x. Snapshot и сторонние прошивки не проверены.' >&2; exit 1 ;;
esac
ram=$(awk '/MemTotal:/{print $2}' /proc/meminfo)
[ "$ram" -ge 220000 ] || { echo 'Нужно не менее 256 МБ RAM.' >&2; exit 1; }
if [ -d /overlay/upper ]; then disk=/overlay; else disk=/; fi
available=$(df -k "$disk" | awk 'END {print $4}')
[ "$available" -ge 51200 ] || { echo 'Освободите не менее 50 МБ постоянного хранилища или настройте extroot.' >&2; exit 1; }
command -v "$manager" >/dev/null
fetch() {
 if command -v uclient-fetch >/dev/null; then uclient-fetch -q -O "$2" "$1";
 elif command -v curl >/dev/null; then curl --fail --silent --show-error --proto '=https' --tlsv1.2 --output "$2" "$1";
 else echo 'В прошивке отсутствует HTTPS-загрузчик uclient-fetch/curl.' >&2; exit 1; fi
}
base=https://overwall.online/downloads/openwrt/0.1.0
if [ "$manager" = apk ]; then
 mkdir -p /etc/apk/keys /etc/apk/repositories.d
 cat > /etc/apk/keys/overwall-apk.pem <<'APKKEY'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4fHc9xzYGy5y7uJi/WD0IpErquBX
HLCRNQV8D27lhDECVlUsnTQEz+mBja9UmqSX/q0yo6FrUvnyQ1jIleAvzQ==
-----END PUBLIC KEY-----
APKKEY
 printf '%s\n' "$base/25.12/packages.adb" > /etc/apk/repositories.d/overwall.list
 apk update
 apk add luci-app-overwall
else
 mkdir -p /etc/opkg/keys
 key=$(mktemp /tmp/overwall-key.XXXXXX)
 trap 'rm -f "$key"' EXIT HUP INT TERM
 cat > "$key" <<'USIGNKEY'
untrusted comment: Overwall OpenWrt feed
RWQo8lK9VkgJMixF+0XjvfNwIz3mYF6DOG5dK9sywBjWQazal8wqTPFv
USIGNKEY
 opkg-key add "$key"
 printf '%s\n' "src/gz overwall $base/24.10" > /etc/opkg/customfeeds.conf.overwall
 # opkg reads *.conf; keep other custom feeds intact.
 mv /etc/opkg/customfeeds.conf.overwall /etc/opkg/overwall.conf
 opkg update
 opkg install luci-app-overwall
fi
printf '\nOverwall VPN установлен. Откройте LuCI → Сервисы → Overwall VPN.\nЗависимости установлены автоматически. Рекомендуется перезагрузить роутер после первой установки.\n'
