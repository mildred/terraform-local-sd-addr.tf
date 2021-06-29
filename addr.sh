
LF=$'\n'

set -e

mkdir -p /run/$UNIT_NAME

touch /run/$UNIT_NAME/hosts
exec 4</run/$UNIT_NAME/hosts
flock --timeout 5 4 || exit 1

update(){
  if [ -w /etc/hosts ]; then
    sed -i "/# BEGIN \/run\/$UNIT_NAME\/hosts/,/# END \/run\/$UNIT_NAME\/hosts/ d" /etc/hosts
    cat /etc/hosts >/etc/.tmp$$-hosts
    echo "# BEGIN /run/$UNIT_NAME/hosts" >>/etc/.tmp$$-hosts
    cat /run/$UNIT_NAME/hosts >>/etc/.tmp$$-hosts
    echo "# END /run/$UNIT_NAME/hosts" >>/etc/.tmp$$-hosts
    mv /etc/.tmp$$-hosts /etc/hosts
  else
    echo >&2 "/etc/hosts: read-only"
  fi
}

up(){
  local NEW_HOST="$1"
  local i prefix ip4 ip6

  if [[ -e /run/$UNIT_NAME/$NEW_HOST.env ]]; then
    echo "/run/$UNIT_NAME/$NEW_HOST.env: already exists" >&2
    echo
    egrep "^\\S* $NEW_HOST ${NEW_HOST}[46]$" /run/$UNIT_NAME/hosts
    echo
    cat "/run/$UNIT_NAME/$NEW_HOST.env"
    return 0
  fi
  prefix=$(echo $ULA_PREFIX | sed 's:/.*::')
  i="$(sed -rn "/^127\\.0\\.0\\.(\\S*) ${NEW_HOST} ${NEW_HOST}4$/ { s//\\1/p; q }" /run/$UNIT_NAME/hosts)"
  if [ -z "$i" ]; then
    update
    i=2
    while egrep -q "^127.0.0.$i " /etc/hosts; do
      i=$((i+1))
    done
  fi
  ip4="127.0.0.$i"
  ip6="$prefix$(printf %""x $i)"
  /usr/bin/sed -ri -e "/^\\S* ${NEW_HOST} ${NEW_HOST}[46]$/d" /run/$UNIT_NAME/hosts
  echo "$ip4 $NEW_HOST $NEW_HOST""4" >>/run/$UNIT_NAME/hosts
  echo "$ip6 $NEW_HOST $NEW_HOST""6" >>/run/$UNIT_NAME/hosts
  mkdir -p /run/$UNIT_NAME
  echo "HOST_$(echo $NEW_HOST | sed 's:-:_:g')6=$ip6" >/run/${UNIT_NAME}/$NEW_HOST.env
  echo "HOST_$(echo $NEW_HOST | sed 's:-:_:g')4=$ip4" >>/run/${UNIT_NAME}/$NEW_HOST.env
  echo "HOSTADDR6=$ip6" >>/run/$UNIT_NAME/$NEW_HOST.env
  echo "HOSTADDR4=$ip4" >>/run/$UNIT_NAME/$NEW_HOST.env
  ip addr add $ip6 dev lo
  update

  echo
  egrep "^\\S* $NEW_HOST ${NEW_HOST}[46]$" /run/$UNIT_NAME/hosts
  echo
  cat "/run/$UNIT_NAME/$NEW_HOST.env"
}

gen(){
  local NEW_HOST="$1"
  local generated=false
  if [ -e "/run/$UNIT_NAME/$NEW_HOST.generated" ]; then
    while read f; do
      if [ "$f" = "$2" ]; then
        generated=true
        break
      fi
    done <"/run/$UNIT_NAME/$NEW_HOST.generated"
  fi
  if ! $generated; then
    echo "$2" >> "/run/$UNIT_NAME/$NEW_HOST.generated"
  fi
  up "$1"
}

down(){
  local NEW_HOST="$1"
  local i prefix ip4 ip6

  if [ -e /run/$UNIT_NAME/$NEW_HOST.generated ]; then
    local generated=()
    while read f; do
      if [ -e "$f" ] && grep "$UNIT_NAME[46]\?@$NEW_HOST" "$f" >/dev/null; then
        generated+=("$f")
      fi
    done <"/run/$UNIT_NAME/$NEW_HOST.generated"
    if [ -n "${generated}" ]; then
      echo >&2 "Cannot stop $UNIT_NAME@$NEW_HOST because generated units depends on it: ${generated[*]}"
      return 1
    else
      rm -f "/run/$UNIT_NAME/$NEW_HOST.generated"
    fi
  fi
  ip6=$(sed -rn "s/.*6=(.*)/\\1/p" /run/$UNIT_NAME/$NEW_HOST.env)
  /usr/bin/sed -ri -e "/^\\S* ${NEW_HOST} ${NEW_HOST}[46]$/d" /run/$UNIT_NAME/hosts
  /bin/rm -f "/run/$UNIT_NAME/${NEW_HOST}.env"
  ip addr del "$ip6" dev lo
  update
}

case "$1" in
  up|down|gen|update)
    "$@"
    ;;
  *)
    echo "$0 gen HOSTNAME GENERATED_FILE"
    echo "$0 up|down HOSTNAME"
    echo "$0 update"
    exit 1
    ;;
esac
