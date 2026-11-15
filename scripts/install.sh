#!/bin/sh
# Overwall VPN installer 0.1.2. HTTPS + signed package repositories.
set -eu
export LC_ALL=C
check_only=0
case "${1:-}" in
 --check) check_only=1 ;;
 '') ;;
 *) echo 'Использование: sh install.sh [--check] (проверка без установки пакетов)' >&2; exit 1 ;;
esac
fail() { printf '\n%s\n' "$*" >&2; exit 1; }
mib() { awk -v kib="$1" 'BEGIN {printf "%.1f", kib / 1024}'; }
free_kib() { df -Pk "$1" | awk 'END {print $4}'; }
# STORAGE_FUNCTIONS_BEGIN
plan_packages() {
 if [ "$manager" = opkg ]; then
  awk '/^(Installing|Upgrading|Reinstalling|Downgrading) / {
   name=$2; line=$0;
   if (line ~ / from .* to /) {sub(/^.* to /,"",line); sub(/[.][.][.]$/,"",line)}
   else {sub(/^[^(]*\(/,"",line); sub(/\).*/,"",line)}
   print name, line
  }' "$1"
 else
  awk '/^\([ ]*[0-9]+\/[0-9]+\) (Installing|Upgrading|Reinstalling|Downgrading|Replacing) / {
   line=$0; sub(/^\([ ]*[0-9]+\/[0-9]+\) /,"",line);
   split(line,fields," "); name=fields[2]; sub(/@.*/,"",name); sub(/^[^(]*\(/,"",line);
   sub(/\).*/,"",line); sub(/^.* -> /,"",line); print name, line
  }' "$1"
 fi
}
opkg_sizes() {
 wanted=$1; wanted_version=$2; shift 2
 awk -v wanted="$wanted" -v version="$wanted_version" '
  BEGIN {RS=""; FS="\n"}
  {p="";v="";s="";d=0; for(i=1;i<=NF;i++) {
   if($i ~ /^Package: /) p=substr($i,10);
   if($i ~ /^Version: /) v=substr($i,10);
   if($i ~ /^Installed-Size: /) s=substr($i,17);
   if($i ~ /^Size: /) d=substr($i,7);
  }
  if(p==wanted && v==version && s ~ /^[0-9]+$/ && s+0>0) {
   if(d+0<=0) d=s;
   print int((s+1023)/1024), int((d+1023)/1024); found=1; exit
  }}
  END {if(!found) exit 1}' "$@"
}
apk_size() {
 # Round up by a whole display unit because apk info rounds human sizes.
 awk 'NF==2 && $1 ~ /^[0-9]+([.][0-9]+)?$/ {
  n=$1+1; u=$2; factor=0;
  if(u=="B" || u=="bytes") factor=1/1024;
  if(u=="KiB" || u=="Ki") factor=1;
  if(u=="MiB" || u=="Mi") factor=1024;
  if(u=="GiB" || u=="Gi") factor=1048576;
  if(factor) {print int(n*factor+1); found=1; exit}
 } END {if(!found) exit 1}'
}
storage_check() {
 available=$(free_kib "$disk")
 temporary=$(free_kib "$work")
 required=$((install_kib + (install_kib + 4) / 5 + 2048))
 tmp_required=$((download_kib + 2048))
 printf '\nПостоянное хранилище (%s): свободно %s МиБ.\n' "$disk" "$(mib "$available")"
 printf 'Пакеты: до %s МиБ; с запасом 20%% + 2 МиБ нужно %s МиБ.\n' "$(mib "$install_kib")" "$(mib "$required")"
 printf 'Временное место (/tmp): свободно %s МиБ; нужно до %s МиБ.\n' "$(mib "$temporary")" "$(mib "$tmp_required")"
 if [ "$available" -lt "$required" ]; then
  printf 'Не хватает %s МиБ постоянного места.\n' "$(mib "$((required - available))")" >&2
  fail 'Освободите место от ненужных установленных пакетов или настройте extroot и повторите установку. Не удаляйте xray-core: Overwall использует его совместно с v2rayA. Размер .ipk при скачивании меньше установленного размера. Пакеты ещё не устанавливались.'
 fi
 [ "$temporary" -ge "$tmp_required" ] || fail 'Недостаточно временного места в /tmp (обычно RAM). Освободите ненужные временные файлы или перезагрузите роутер и повторите установку. Пакеты ещё не устанавливались.'
}
# STORAGE_FUNCTIONS_END
[ "$(id -u)" = 0 ] || fail 'Запустите от root.'
[ -r /etc/openwrt_release ] || fail 'Нужен OpenWrt.'
. /etc/openwrt_release
case "$DISTRIB_RELEASE" in
 25.12.*) manager=apk ;;
 24.10.*) manager=opkg ;;
 *) fail 'Поддерживаются стабильные OpenWrt 25.12.x и 24.10.x. Snapshot и сторонние прошивки не проверены.' ;;
esac
ram=$(awk '/MemTotal:/{print $2}' /proc/meminfo)
[ "$ram" -ge 220000 ] || fail 'Нужно не менее 256 МБ RAM.'
if [ -d /overlay/upper ]; then disk=/overlay; else disk=/; fi
command -v "$manager" >/dev/null || fail "Не найден пакетный менеджер $manager. Нужна штатная поддерживаемая OpenWrt."
work=$(mktemp -d /tmp/overwall-install.XXXXXX) || fail 'Не удалось создать временную папку в /tmp.'
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
printf 'Overwall VPN: OpenWrt %s, %s, RAM %s МиБ.\n' "$DISTRIB_RELEASE" "$(uname -m)" "$(mib "$ram")"
if [ -x /usr/bin/xray ]; then
 echo 'Xray уже найден. Установленная совместимая зависимость будет использована без второй копии.'
fi
if [ -x /etc/init.d/v2raya ]; then
 echo 'Найден v2rayA. Перед включением VPN в Overwall отключите прозрачное проксирование в v2rayA, чтобы правила маршрутизации не конфликтовали.'
fi
[ "$(free_kib "$disk")" -ge 2048 ] || fail 'Свободно менее 2 МиБ постоянного места. Освободите место перед добавлением репозитория. Пакеты ещё не устанавливались.'
base=https://overwall.online/downloads/openwrt/0.1.2
repo_error='Не удалось обновить репозитории. Проверьте интернет, DNS и дату на роутере (для HTTPS). Ошибки выше указывают проблемный репозиторий; отключите устаревшие сторонние feeds и повторите установку.'
if [ "$manager" = apk ]; then
 mkdir -p /etc/apk/keys /etc/apk/repositories.d
 cat > /etc/apk/keys/overwall-apk.pem <<'APKKEY'
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4fHc9xzYGy5y7uJi/WD0IpErquBX
HLCRNQV8D27lhDECVlUsnTQEz+mBja9UmqSX/q0yo6FrUvnyQ1jIleAvzQ==
-----END PUBLIC KEY-----
APKKEY
 printf '%s\n' "$base/25.12/packages.adb" > /etc/apk/repositories.d/overwall.list
 apk update || fail "$repo_error"
else
 mkdir -p /etc/opkg/keys
 key=$work/key
 cat > "$key" <<'USIGNKEY'
untrusted comment: Overwall OpenWrt feed
RWQo8lK9VkgJMixF+0XjvfNwIz3mYF6DOG5dK9sywBjWQazal8wqTPFv
USIGNKEY
 opkg-key add "$key"
 printf '%s\n' "src/gz overwall $base/24.10" > /etc/opkg/customfeeds.conf.overwall
 mv /etc/opkg/customfeeds.conf.overwall /etc/opkg/overwall.conf
 opkg update || fail "$repo_error"
fi
lists_dir=/var/opkg-lists
if [ "$manager" = opkg ]; then
 configured_lists=$(awk '$1=="lists_dir" {print $3}' /etc/opkg.conf /etc/opkg/*.conf 2>/dev/null | tail -n 1)
 [ -z "$configured_lists" ] || lists_dir=$configured_lists
 [ -d "$lists_dir" ] || fail "Не найден каталог индексов $lists_dir после обновления репозиториев."
fi
echo 'Проверяю зависимости без установки пакетов. opkg может скачать архивы в /tmp для проверки…'
if [ "$manager" = opkg ]; then
 opkg --noaction --tmp-dir "$work" install luci-app-overwall > "$work/plan" 2>&1 && plan_ok=1 || plan_ok=0
else
 apk add --simulate --no-progress luci-app-overwall > "$work/plan" 2>&1 && plan_ok=1 || plan_ok=0
fi
cat "$work/plan"
[ "$plan_ok" = 1 ] || fail 'Не удалось подобрать зависимости. Проверьте также свободное место в /tmp и интернет. Если выше указаны kernel/kmod или incompatible architecture, нужны пакеты строго для вашей версии прошивки. Не используйте --force-depends или --force-space. Пакеты ещё не устанавливались.'
plan_packages "$work/plan" | sort -u > "$work/packages"
install_kib=0
download_kib=0
echo 'Пакеты, которые нужно добавить или обновить (уже подходящие зависимости сюда не входят):'
while read -r name version; do
 [ -n "$name" ] || continue
 case "$name" in *[!a-zA-Z0-9+_.-]*) fail "Не удалось разобрать имя пакета: $name" ;; esac
 if [ "$manager" = opkg ]; then
  # opkg info omits Installed-Size; read the indexes verified by opkg update.
  if sizes=$(opkg_sizes "$name" "$version" "$lists_dir"/*); then
   set -- $sizes; size=$1; compressed=$2
  else
   # Old Overwall IPK indexes omit Installed-Size. Each payload is <100 KiB;
   # reserve 256 KiB per package, including package metadata.
   case "$name" in
    overwall-client|luci-app-overwall) size=256; compressed=256 ;;
    *) fail "Репозиторий не сообщил установленный размер $name ($version). Без достоверного расчёта установка остановлена. Обновите feeds и повторите." ;;
   esac
  fi
 else
  apk info --size "$name=$version" > "$work/info" || fail "Не удалось прочитать размер пакета $name."
  size=$(apk_size < "$work/info") || fail "Не удалось определить установленный размер $name. Установка остановлена; пакеты ещё не устанавливались."
  compressed=$size
 fi
 install_kib=$((install_kib + size))
 download_kib=$((download_kib + compressed))
 printf '  %s %s — до %s МиБ\n' "$name" "$version" "$(mib "$size")"
done < "$work/packages"
if [ ! -s "$work/packages" ]; then
 if ! { grep -q 'up to date' "$work/plan" || grep -q '^OK:' "$work/plan"; }; then
  fail 'Не удалось распознать план установки. Пакеты ещё не устанавливались; сохраните вывод выше для диагностики.'
 fi
 echo '  Все пакеты уже установлены.'
fi
storage_check
if [ "$check_only" = 1 ]; then
 echo 'Проверка пройдена. Пакеты не устанавливались. Запустите этот же установщик без --check для установки.'
 exit 0
fi
echo 'Места достаточно. Устанавливаю Overwall VPN…'
if [ "$manager" = opkg ]; then
 opkg --tmp-dir "$work" install luci-app-overwall && installed=1 || installed=0
else
 apk add --no-cache luci-app-overwall && installed=1 || installed=0
fi
[ "$installed" = 1 ] || fail 'Установка не завершена. Смотрите ошибку выше: проверьте интернет и свободное место; для ошибок kernel/kmod используйте feeds своей прошивки. После устранения причины повторите установщик. Часть зависимостей могла установиться; повторный запуск учтёт их.'
printf '\nOverwall VPN установлен. Откройте LuCI → Сервисы → Overwall VPN.\nЕсли меню не появилось, обновите страницу LuCI с очисткой кеша.\nПеред подключением отключите другие службы прозрачного VPN/прокси (например, v2rayA).\nВыберите сервер и подключитесь. Рекомендуется перезагрузить роутер после первой установки.\n'
