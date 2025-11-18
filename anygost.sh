#!/bin/bash


shell_version="1.1.0"


C_GREEN="\033[92m"
C_RED="\033[31m"
C_BG_GREEN="\033[42;37m"
C_RESET="\033[0m"
XRAY_LABEL="Xray Reality+Vision"
STATUS_RUNNING="${C_GREEN}运行中${C_RESET}"
STATUS_STOPPED="${C_RED}已停止${C_RESET}"


LINE_HEAVY="━━━━━━━━━━━━━━━━━━━━"
LINE_LIGHT="────────────────────"
LINE_BOX="════════════════════"
LINE_TABLE="────────────────────"


WORKDIR="/root/net-tools-anygost"
gost_conf_path="$WORKDIR/gost-config.json"
raw_conf_path="$WORKDIR/rawconf"


PORT_MIN=10000
PORT_MAX=20000
PORT_TRIES=200


SS_DEFAULT="aes-128-gcm"
REALITY_PUBLIC_KEY="MIwVa4SS-dxn6amHA_a3rN2OyHsUu1N_jaC-k-aHUGk"
REALITY_SNI_OPTIONS=(
  "www.adobe.com"
  "www.amazon.com"
  "aws.amazon.com"
  "www.apple.com"
  "www.cloudflare.com"
  "www.dell.com"
  "www.intel.com"
  "www.microsoft.com"
  "www.office.com"
  "www.w3schools.com"
  "cdnjs.com"
  "www.freecodecamp.org"
  "www.tutorialspoint.com"
  "www.geeksforgeeks.org"
  "www.programiz.com"
  "www.jsdelivr.com"
)


PASSWORD_LENGTH=16
GOST_IMAGE="ginuerzh/gost:2.12"
SERVICE_STATUS_LIST=(xray anytls gost shadowsocks)


generate_random_password() {
  local length=${1:-$PASSWORD_LENGTH}
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c"$length"
}


encode_base64_clean() {
  local input="$1"
  printf '%s' "$input" | base64 2>/dev/null | tr -d '\n' | tr -d '\r'
}


generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

pad_cell() {
  local text="$1" align="${3:-left}"
  local width="${2:-0}"
  local text_len=${#text}

  if [ "$text_len" -ge "$width" ] || [ "$width" -le 0 ]; then
    printf '%s' "$text"
    return
  fi

  local pad=$((width - text_len))
  local left=0
  local right=0

  case "$align" in
    center)
      left=$((pad / 2))
      right=$((pad - left))
      ;;
    right)
      left=$pad
      ;;
    *)
      right=$pad
      ;;
  esac

  printf '%*s%s%*s' "$left" '' "$text" "$right" ''
}

ensure_workdir() {
  mkdir -p "$WORKDIR"
}

ensure_gost_resources() {
  ensure_workdir

  if [ ! -f "$raw_conf_path" ]; then
    touch "$raw_conf_path"
    chmod 644 "$raw_conf_path" 2>/dev/null || true
  fi

  if [ ! -f "$gost_conf_path" ]; then
    printf '%s\n' "$config_json_content" >"$gost_conf_path"
    chmod 644 "$gost_conf_path" 2>/dev/null || true
  fi
}

pause_with_prompt() {
  local prompt="${1:-按回车继续...}"
  read -p "$prompt"
}


show_success() {
  local message="$1"
  echo -e "${C_GREEN}✓${C_RESET} $message"
}


show_error() {
  local message="$1"
  echo -e "${C_RED}✗${C_RESET} $message"
}


show_info() {
  local message="$1"
  echo -e "  $message"
}


show_service_info() {
  local title="$1"
  local server="$2"
  local port="$3"
  local extra="$4"

  echo
  show_success "$title 部署完成"
  show_info "服务器: $server"
  show_info "端口: $port"
  [[ -n "$extra" ]] && show_info "$extra"
}


show_menu_title() {
  local title="$1"
  echo
  printf '  %b\n' "${C_GREEN}${title}${C_RESET}"
  printf '  %s\n' "${LINE_HEAVY}"
}


show_option() {
  local num="$1"
  local desc="$2"
  echo -e "  ${C_GREEN}${num}.${C_RESET} ${desc}"
}



check_service_status() {
  local service_name="$1"
  local docker_names="$2"
  local status_info=""

  case "$service_name" in
    "xray")
      if printf '%s\n' "$docker_names" | grep -q "^anygostxray$"; then
        status_info="${C_GREEN}●${C_RESET} ${XRAY_LABEL} 服务端"
      elif [ -f "$WORKDIR/xray-config.json" ]; then
        status_info="${C_RED}●${C_RESET} ${XRAY_LABEL} 服务端 (已停止)"
      fi
      ;;
    "anytls")
      if systemctl is-active --quiet anytls; then
        status_info="${C_GREEN}●${C_RESET} AnyTLS 服务端"
      elif [ -f "$WORKDIR/anytls-config.json" ]; then
        status_info="${C_RED}●${C_RESET} AnyTLS 服务端 (已停止)"
      fi
      ;;
    "gost")
      if printf '%s\n' "$docker_names" | grep -q "^anygostgost$"; then
        status_info="${C_GREEN}●${C_RESET} GOST 服务端"
      elif [ -f "$gost_conf_path" ]; then
        status_info="${C_RED}●${CRESET} GOST 服务端 (已停止)"
      fi
      ;;
    "shadowsocks")
      if [ -f "$raw_conf_path" ] && grep -q "^ss/" "$raw_conf_path" 2>/dev/null; then
        if printf '%s\n' "$docker_names" | grep -q "^anygostgost$"; then
          status_info="${C_GREEN}●${C_RESET} Shadowsocks 服务端"
        else
          status_info="${C_RED}●${C_RESET} Shadowsocks 服务端 (已停止)"
        fi
      fi
      ;;
  esac

  if [[ -n "$status_info" ]]; then
    echo -e "  $status_info"
  fi
}


show_services_status() {
  local has_services=false

  echo
  printf '  %b\n' "${C_GREEN}服务运行状态${C_RESET}"

  local docker_names=""
  if command -v docker >/dev/null 2>&1; then
    docker_names=$(docker ps --format '{{.Names}}' 2>/dev/null)
  fi

  local service status
  for service in "${SERVICE_STATUS_LIST[@]}"; do
    status=$(check_service_status "$service" "$docker_names")
    if [[ -n "$status" ]]; then
      echo -e "$status"
      has_services=true
    fi
  done

  if [ "$has_services" = false ]; then
    show_info "暂无已部署的服务"
  fi
}


config_json_content='{"Debug":true,"Retries":0,"ServeNodes":[],"ChainNodes":[],"Routes":[]}'


guard_gost() {
  if [ -f "$raw_conf_path" ]; then

    local content=$(grep -v "^[[:space:]]*$" "$raw_conf_path" 2>/dev/null)
    if [[ -z "$content" ]]; then
      echo "检测到GOST配置为空，停止容器以避免持续重启"
      docker stop anygostgost 2>/dev/null || true
      docker rm anygostgost 2>/dev/null || true
      return 0
    fi
  fi
  return 1
}


install_ss_server() {
  ensure_workdir

  # 确保 Docker 和 GOST 镜像可用
  if ! auto_install_docker_and_gost; then
    return 1
  fi

  local PASS PORT
  PASS=$(generate_random_password)
  pick_port "ss 端口(回车随机$PORT_MIN-$PORT_MAX): " "$PORT_MIN" "$PORT_MAX" || return 1
  PORT="$CHOSEN_PORT"


  touch "$raw_conf_path"
  local ss_entry="ss/${PASS}#${SS_DEFAULT}#${PORT}"
  if grep -q '^ss/' "$raw_conf_path" 2>/dev/null; then
    local tmpfile
    tmpfile=$(mktemp)
    awk -v newline="$ss_entry" '
      BEGIN {replaced=0}
      /^ss\// && replaced==0 {print newline; replaced=1; next}
      {print}
      END {if(replaced==0) print newline}
    ' "$raw_conf_path" >"$tmpfile"
    mv "$tmpfile" "$raw_conf_path"
  else
    echo "$ss_entry" >> "$raw_conf_path"
  fi
  chmod 644 "$raw_conf_path" 2>/dev/null || true


  local gost_container_exists=false
  if docker ps -a --format '{{.Names}}' | grep -q '^anygostgost$'; then
    gost_container_exists=true
  fi
  if [ "$gost_container_exists" = false ]; then
    echo "未检测到 gost 容器，正在自动安装..."
    Install_ct
  else
    show_info "检测到已有 GOST 容器，更新 Shadowsocks 服务端配置..."
  fi


  if ! regenerate_gost_config; then
    show_error "GOST 容器启动失败"
    return 1
  fi


  local ip
  ip=$(get_public_ip)

  echo
  show_success "Shadowsocks 服务端 部署完成"
  printf '  服务器: %s  端口: %s | 加密: %s | 密码: %s\n' "$ip" "$PORT" "$SS_DEFAULT" "$PASS"
  local creds b64 tag
  creds="${SS_DEFAULT}:${PASS}"
  b64=$(encode_base64_clean "$creds")
  b64=$(url_encode "$b64")
  tag=$(url_encode "$ip")
  local link="ss://${b64}@${ip}:${PORT}#${tag}"
  local qr_url="https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
  printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "$qr_url"
}

check_sys() {
  if [[ -f /etc/redhat-release ]]; then
    release="centos"
  elif cat /etc/issue | grep -q -E -i "debian"; then
    release="debian"
  elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="ubuntu"
  elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
  elif cat /proc/version | grep -q -E -i "debian"; then
    release="debian"
  elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="ubuntu"
  elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
  fi
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    return 0
  fi

  check_sys
  echo -e "未检测到 Docker，正在安装..."
  if [[ ${release} == "centos" ]]; then
    yum install -y docker || yum install -y docker-ce
  else
    apt-get update
    apt-get install -y docker.io || apt-get install -y docker-ce || true
  fi
  systemctl enable docker 2>/dev/null || true
  systemctl start docker 2>/dev/null || true
}

install_deps() {
  gzip_ver=$(gzip -V)
  if [[ -z ${gzip_ver} ]]; then
    if [[ ${release} == "centos" ]]; then
      yum update
      yum install -y gzip wget
    else
      apt-get update
      apt-get install -y gzip wget
    fi
  fi
}

check_root() {
  [[ $EUID != 0 ]] && echo -e "${C_RED}[错误]${C_RESET} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${C_BG_GREEN}sudo su${C_RESET} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

check_file() {
  if test ! -d "/usr/lib/systemd/system/"; then
    mkdir /usr/lib/systemd/system
    chmod -R 777 /usr/lib/systemd/system
  fi
}

check_nor_file() {
  rm -rf "$(pwd)"/gost
  rm -rf "$(pwd)"/gost.service
  rm -rf "$(pwd)"/config.json

  rm -rf /usr/lib/systemd/system/gost.service
  rm -rf /usr/bin/gost
}


find_free_port() {
  local start_port=${1:-8443}
  local port=$start_port
  while ss -tuln 2>/dev/null | grep -q ":$port "; do
    port=$((port+1))
    if [ $port -gt 65535 ]; then
      echo 0
      return
    fi
  done
  echo $port
}


is_port_free() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -tuln 2>/dev/null | grep -q ":$port " && return 1 || return 0
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tuln 2>/dev/null | grep -q ":$port " && return 1 || return 0
  else
    lsof -i ":$port" 2>/dev/null | grep -q ":$port" && return 1 || return 0
  fi
}

pick_port() {
  local prompt="$1" min=${2:-$PORT_MIN} max=${3:-$PORT_MAX} input port tries=$PORT_TRIES
  read -e -p "$prompt" input || true
  if [[ -z "$input" ]]; then
    while [ $tries -gt 0 ]; do
      port=$((RANDOM % (max - min + 1) + min))
      is_port_free "$port" && break
      port=""
      tries=$((tries-1))
    done
  elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]; then
    if is_port_free "$input"; then
      port="$input"
    else
      echo "端口已占用"
      return 1
    fi
  else
    echo "端口无效"
    return 1
  fi

  if [ -z "$port" ]; then
    echo "未找到可用端口"
    return 1
  fi

  CHOSEN_PORT="$port"
  return 0
}


get_public_ip() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}' | sed -n '1p')
  if echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    echo "$ip"; return
  fi
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d'/' -f1 | head -n1)
    if echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      echo "$ip"; return
    fi
  fi
  for u in "https://ipinfo.io/ip" "https://api.ip.sb/ip" "https://ipv4.icanhazip.com"; do
    ip=$(curl -fsSL "$u" 2>/dev/null | tr -d ' \r\n')
    if echo "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
      echo "$ip"; return
    fi
  done
  echo ""
}


url_encode() {
  local s="$1" i c o safe='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
  o=''
  for ((i=0;i<${#s};i++)); do
    c="${s:i:1}"
    if [[ "$safe" == *"$c"* ]]; then o+="$c"; else printf -v o '%s%%%02X' "$o" "'${c}"; fi
  done
  printf '%s' "$o"
}


install_xray_reality() {
  local XRAY_CONFIG="${WORKDIR}/xray-config.json"
  local CONTAINER_NAME="anygostxray"
  local XRAY_IMAGE="ghcr.io/xtls/xray-core:latest"

  # 确保 Docker 可用
  if ! command -v docker >/dev/null 2>&1; then
    if ! auto_install_docker_and_gost; then
      return 1
    fi
  fi

  pick_port "xray 端口(回车随机10000-20000): " 10000 20000 || return 1
  local LISTEN_PORT="$CHOSEN_PORT"


  local USER_UUID SHORT_ID
  USER_UUID=$(generate_uuid)

  SHORT_ID=$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')


  local PRIVATE_KEY="4F7NbSiRp6iVq5pKIFhzUipCCGTPUsxmLRZQRp6Y404"
  local PUBLIC_KEY="$REALITY_PUBLIC_KEY"
  local raw_sni_index=$((RANDOM % ${#REALITY_SNI_OPTIONS[@]}))
  local DEST_HOST="${REALITY_SNI_OPTIONS[$raw_sni_index]}"

  ensure_workdir
  cat > "$XRAY_CONFIG" <<EOF
{"log":{"loglevel":"warning"},"inbounds":[{"tag":"vless-reality-vision","listen":"0.0.0.0","port":${LISTEN_PORT},"protocol":"vless","settings":{"clients":[{"id":"${USER_UUID}","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"dest":"${DEST_HOST}:443","serverNames":["${DEST_HOST}"],"privateKey":"${PRIVATE_KEY}","shortIds":["${SHORT_ID}"],"show":false},"xtlsSettings":{"minVersion":"1.3"}},"sniffing":{"enabled":true,"destOverride":["http","tls"]}}],"outbounds":[{"protocol":"freedom","tag":"direct"},{"protocol":"blackhole","tag":"block"}],"routing":{"rules":[{"type":"field","protocol":["bittorrent"],"outboundTag":"block"}]}}
EOF

  ensure_docker
  local container_exists=false
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
    container_exists=true
  fi

  if [ "$container_exists" = true ]; then
    docker restart "$CONTAINER_NAME" 2>/dev/null || {
      docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
      docker run -d --name "$CONTAINER_NAME" --network host --restart unless-stopped \
        -v "$XRAY_CONFIG":/data/config.json "$XRAY_IMAGE" run -c /data/config.json
    }
  else
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    docker pull "$XRAY_IMAGE"
    docker run -d --name "$CONTAINER_NAME" --network host --restart unless-stopped \
      -v "$XRAY_CONFIG":/data/config.json "$XRAY_IMAGE" run -c /data/config.json
  fi
  local server_ip; server_ip=$(get_public_ip)

  echo
  show_success "${XRAY_LABEL} 部署完成"
  printf '  服务器: %s  端口: %s | UUID: %s\n' "$server_ip" "$LISTEN_PORT" "$USER_UUID"
  printf '  SNI   : %-24s | ShortID: %s\n' "$DEST_HOST" "$SHORT_ID"
  local link="vless://${USER_UUID}@${server_ip}:${LISTEN_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST_HOST}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#Xray-Reality"
  local qr_url="https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
  printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "$qr_url"
}


install_anytls() {
  local ENV_FILE="${WORKDIR}/anytls-config.json"
  local SERVICE_NAME="anytls"
  local SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
  local BIN_SERVER="/usr/local/bin/anytls-server"
  local BIN_CLIENT="/usr/local/bin/anytls-client"

  local ARCH
  case "$(uname -m)" in
    x86_64|amd64)  ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    armv7l|armv7)  ARCH=armv7 ;;
    *) echo "不支持的架构: $(uname -m)"; return 2 ;;
  esac


  local PORT PASS
  pick_port "anytls 端口(回车随机$PORT_MIN-$PORT_MAX): " "$PORT_MIN" "$PORT_MAX" || return 1
  PORT="$CHOSEN_PORT"
  PASS=$(generate_random_password)

  ensure_workdir
  local service_exists=false
  if systemctl list-unit-files --no-legend --no-pager 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
    service_exists=true
  elif systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null || systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    service_exists=true
  elif [ -f "$SERVICE_FILE" ]; then
    service_exists=true
  fi

  local TAG=""
  if [ -f "$ENV_FILE" ]; then
    TAG=$(grep -E '^TAG=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2-)
  fi

  if [ "$service_exists" = false ] || [ ! -x "$BIN_SERVER" ]; then
    local JSON
    JSON=$(curl -fsSL "https://api.github.com/repos/anytls/anytls-go/releases/latest")
    TAG=$(echo "$JSON" | sed -n 's/.*"tag_name": *"\([^"]\+\)".*/\1/p' | head -n1)
    [ -z "$TAG" ] && TAG=v0.2.5
    local BASE="anytls_${TAG#v}_linux_${ARCH}"
    local TMP
    TMP=$(mktemp -d)
    if curl -fsI "https://github.com/anytls/anytls-go/releases/download/${TAG}/${BASE}.tar.gz" >/dev/null 2>&1; then
      curl -fL "https://github.com/anytls/anytls-go/releases/download/${TAG}/${BASE}.tar.gz" -o "$TMP/${BASE}.tar.gz"
      tar -xzf "$TMP/${BASE}.tar.gz" -C "$TMP"
    else
      curl -fL "https://github.com/anytls/anytls-go/releases/download/${TAG}/${BASE}.zip" -o "$TMP/${BASE}.zip"
      unzip -q "$TMP/${BASE}.zip" -d "$TMP"
    fi
    install -m0755 "$TMP/anytls-server" "$BIN_SERVER"
    [ -f "$TMP/anytls-client" ] && install -m0755 "$TMP/anytls-client" "$BIN_CLIENT" || true
    rm -rf "$TMP"
  elif [ -z "$TAG" ]; then
    TAG=v0.2.5
  fi


  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=AnyTLS Server
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=${BIN_SERVER} -l 0.0.0.0:${PORT} -p ${PASS}
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF


  echo "PORT=${PORT}" > "$ENV_FILE"
  echo "PASS=${PASS}" >> "$ENV_FILE"
  echo "TAG=${TAG}" >> "$ENV_FILE"

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
  if [ "$service_exists" = true ]; then
    systemctl restart "$SERVICE_NAME"
  else
    systemctl start "$SERVICE_NAME"
  fi


  sleep 2

  local host; host=$(get_public_ip)
  echo
  show_success "AnyTLS 部署完成"
  printf '  服务器: %s  端口: %s | 密码: %s\n' "$host" "$PORT" "$PASS"
  local link="anytls://$(url_encode "$PASS")@${host}:${PORT}?security=tls&allowInsecure=1&type=tcp#${host}"
  local qr_url="https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
  printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "$qr_url"


  if systemctl is-active --quiet "$SERVICE_NAME"; then
    show_success "服务运行正常"
  else
    show_error "服务启动失败"
    show_info "检查日志: systemctl status anytls"
    show_info "常见问题: 端口被占用或权限不足"
  fi
}


build_server_menu() {
  show_menu_title "服务端搭建"
  show_option "1" "${XRAY_LABEL} - 高性能抗封锁协议"
  show_option "2" "AnyTLS 加密隧道 - 轻量级 TLS 伪装"
  show_option "3" "GOST 多协议代理 - 功能全面的转发平台"
  show_option "4" "Shadowsocks 服务端 - 经典加密代理"
  echo
  read -e -p "请选择 [1-4]: " build_num


  if [[ -z "$build_num" ]]; then
    return
  fi

  case "$build_num" in
    1)
      install_xray_reality
      ;;
    2)
      install_anytls
      ;;
    3)
      Install_ct
      ;;
    4)
      install_ss_server
      ;;
    *)
      show_error "无效选择"
      ;;
  esac


  echo
  pause_with_prompt "🎉 搭建完成！按回车键返回主菜单..."
}


show_all_services_info() {
  local has_services=false

  show_menu_title "已部署服务连接信息"

  local ip_cached=""
  ip_cached=$(get_public_ip)


  local XRAY_CONFIG="/root/net-tools-anygost/xray-config.json"
  if [ -f "$XRAY_CONFIG" ]; then
    has_services=true
    local ip port uuid sni pbk sid
    ip="${ip_cached}"
    if [ -z "$ip" ]; then
      ip=$(get_public_ip)
      ip_cached="$ip"
    fi
    port=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]\+' "$XRAY_CONFIG" | grep -o '[0-9]\+')
    uuid=$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$XRAY_CONFIG" | cut -d'"' -f4)
    sni=$(grep -o '"serverNames"[[:space:]]*:[[:space:]]*\["[^"]*"' "$XRAY_CONFIG" | sed -n 's/.*\["\([^"]*\)"/\1/p' | head -n1)
    sid=$(grep -o '"shortIds"[[:space:]]*:[[:space:]]*\["[^"]*"' "$XRAY_CONFIG" | sed -n 's/.*\["\([^"]*\)"/\1/p' | head -n1)
    pbk="MIwVa4SS-dxn6amHA_a3rN2OyHsUu1N_jaC-k-aHUGk"

    echo
    show_success "${XRAY_LABEL} 连接"
    local link="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&type=tcp&headerType=none#Xray-Reality"
    printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
    printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  fi


  local ANYTLS_CONFIG="/root/net-tools-anygost/anytls-config.json"
  if [ -f "$ANYTLS_CONFIG" ]; then
    has_services=true
    . "$ANYTLS_CONFIG"
    local ip enc
    ip="${ip_cached}"
    if [ -z "$ip" ]; then
      ip=$(get_public_ip)
      ip_cached="$ip"
    fi
    enc=$(url_encode "$PASS")

    echo
    show_success "AnyTLS 连接"
    local link="anytls://${enc}@${ip}:${PORT}?security=tls&allowInsecure=1&type=tcp#${ip}"
    printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
    printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  fi


  if [ -f "$raw_conf_path" ] && grep -q "^ss/" "$raw_conf_path" 2>/dev/null; then
    has_services=true
    local ss_line pass port encrypt creds b64 tag ip
    ss_line=$(grep "^ss/" "$raw_conf_path" 2>/dev/null | head -n1)
    pass=$(echo "$ss_line" | cut -d'/' -f2 | cut -d'#' -f1)
    encrypt=$(echo "$ss_line" | cut -d'#' -f2)
    port=$(echo "$ss_line" | cut -d'#' -f3)
    ip="${ip_cached}"
    if [ -z "$ip" ]; then
      ip=$(get_public_ip)
      ip_cached="$ip"
    fi

    creds="${encrypt}:${pass}"
    b64=$(encode_base64_clean "$creds")
    b64=$(url_encode "$b64")
    tag=$(url_encode "$ip")

    echo
    show_success "Shadowsocks 连接"
    local link="ss://${b64}@${ip}:${port}#${tag}"
    printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
    printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  fi

  if [ "$has_services" = false ]; then
    echo -e ""
    show_info "暂无已部署的服务，请先部署服务端"
  fi

  echo
}


service_management_menu() {
  while true; do

    show_all_services_info

    show_menu_title "服务管理"
    show_option "1" "${XRAY_LABEL} 管理"
    show_option "2" "AnyTLS 服务管理"
    show_option "3" "Shadowsocks 服务端管理"
    show_option "0" "返回主菜单"
    echo
    read -e -p "请选择 [0-3]: " service_choice


    if [[ -z "$service_choice" ]]; then
      break
    fi

    case "$service_choice" in
      1) manage_xray_service ;;
      2) manage_anytls_service ;;
      3) manage_ss_service ;;
      0) break ;;
      *) echo -e "无效选项，请重新选择"; sleep 1 ;;
    esac
  done
}


manage_xray_service() {
  local XRAY_CONFIG="/root/net-tools-anygost/xray-config.json"
  local CONTAINER_NAME="anygostxray"


  if [ ! -f "$XRAY_CONFIG" ]; then
    echo -e "Xray 服务未部署，请先搭建服务端"
    pause_with_prompt "按回车返回..." && return
  fi

  while true; do
    echo "$LINE_BOX"
    echo -e "${XRAY_LABEL} 服务管理"
    echo "$LINE_BOX"


    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      echo -e "服务状态: ${STATUS_RUNNING}"
    else
      echo -e "服务状态: ${STATUS_STOPPED}"
    fi


    local current_port=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]\+' "$XRAY_CONFIG" | grep -o '[0-9]\+')
    local current_uuid=$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$XRAY_CONFIG" | cut -d'"' -f4)
    local current_sni=$(grep -o '"serverNames"[[:space:]]*:[[:space:]]*\["[^"]*"' "$XRAY_CONFIG" | sed -n 's/.*\["\([^"]*\)"/\1/p' | head -n1)
    local current_sid=$(grep -o '"shortIds"[[:space:]]*:[[:space:]]*\["[^"]*"' "$XRAY_CONFIG" | sed -n 's/.*\["\([^"]*\)"/\1/p' | head -n1)

    echo -e "当前端口: ${current_port:-未知}"
    echo -e "当前UUID: ${current_uuid:-未知}"
    echo -e "当前SNI: ${current_sni:-未知}"
    echo -e "当前ShortID: ${current_sid:-未知}"
    echo "$LINE_BOX"
    echo -e "[1] 显示连接信息"
    echo -e "[2] 更新Docker镜像"
    echo -e "[3] 修改监听端口"
    echo -e "[4] 重新生成UUID"
    echo -e "[5] 修改SNI伪装域名"
    echo -e "[6] 查看服务日志"
    echo -e "[7] 重启服务"
    echo -e "[8] 停止服务"
    echo -e "[0] 返回上级菜单"
    echo "$LINE_BOX"
    read -e -p "请选择操作 [0-8]: " xray_choice


    if [[ -z "$xray_choice" ]]; then
      break
    fi

    case "$xray_choice" in
      1) show_xray_connection_info "$XRAY_CONFIG" "$CONTAINER_NAME" ;;
      2) update_xray_docker "$CONTAINER_NAME" ;;
      3) modify_xray_port "$XRAY_CONFIG" "$CONTAINER_NAME" ;;
      4) regenerate_xray_uuid "$XRAY_CONFIG" "$CONTAINER_NAME" ;;
      5) modify_xray_sni "$XRAY_CONFIG" "$CONTAINER_NAME" ;;
      6) show_xray_logs "$CONTAINER_NAME" ;;
      7) restart_xray_service "$CONTAINER_NAME" ;;
      8) stop_xray_service "$CONTAINER_NAME" ;;
      0) break ;;
      *) echo -e "无效选项，请重新选择"; sleep 1 ;;
    esac

    [ "$xray_choice" != "6" ] && pause_with_prompt && sleep 1
  done
}


manage_anytls_service() {
  local ANYTLS_CONFIG="/root/net-tools-anygost/anytls-config.json"
  local SERVICE_NAME="anytls"


  if [ ! -f "$ANYTLS_CONFIG" ]; then
    echo -e "AnyTLS 服务未部署，请先搭建服务端"
    pause_with_prompt "按回车返回..." && return
  fi

  while true; do
    echo "$LINE_BOX"
    echo -e "AnyTLS 服务管理"
    echo "$LINE_BOX"


    if systemctl is-active --quiet "$SERVICE_NAME"; then
      echo -e "服务状态: ${STATUS_RUNNING}"
    else
      echo -e "服务状态: ${STATUS_STOPPED}"
    fi


    if [ -f "$ANYTLS_CONFIG" ]; then
      . "$ANYTLS_CONFIG"
      echo -e "当前端口: ${PORT:-未知}"
      echo -e "当前密码: ${PASS:-未知}"
    fi

    echo "$LINE_BOX"
    echo -e "[1] 显示连接信息"
    echo -e "[2] 更新AnyTLS程序"
    echo -e "[3] 修改监听端口"
    echo -e "[4] 重新生成密码"
    echo -e "[5] 查看服务日志"
    echo -e "[6] 重启服务"
    echo -e "[7] 停止服务"
    echo -e "[0] 返回上级菜单"
    echo "$LINE_BOX"
    read -e -p "请选择操作 [0-7]: " anytls_choice


    if [[ -z "$anytls_choice" ]]; then
      break
    fi

    case "$anytls_choice" in
      1) show_anytls_connection_info "$ANYTLS_CONFIG" ;;
      2) update_anytls_binary ;;
      3) modify_anytls_port "$ANYTLS_CONFIG" ;;
      4) regenerate_anytls_password "$ANYTLS_CONFIG" ;;
      5) show_anytls_logs "$SERVICE_NAME" ;;
      6) restart_anytls_service "$SERVICE_NAME" ;;
      7) stop_anytls_service "$SERVICE_NAME" ;;
      0) break ;;
      *) echo -e "无效选项，请重新选择"; sleep 1 ;;
    esac

    [ "$anytls_choice" != "5" ] && pause_with_prompt && sleep 1
  done
}


manage_ss_service() {
  if [ ! -f "$raw_conf_path" ]; then
    echo -e "Shadowsocks 服务端未配置，请先搭建服务端"
    pause_with_prompt "按回车返回..." && return
  fi


  if ! grep -q "^ss/" "$raw_conf_path" 2>/dev/null; then
    echo -e "未找到 Shadowsocks 服务端配置，请先搭建 SS 服务端"
    pause_with_prompt "按回车返回..." && return
  fi

  while true; do
    echo "$LINE_BOX"
    echo -e "Shadowsocks 服务端管理"
    echo "$LINE_BOX"


    if docker ps --format '{{.Names}}' | grep -q '^anygostgost$'; then
      echo -e "服务状态: ${STATUS_RUNNING}"
    else
      echo -e "服务状态: ${STATUS_STOPPED}"
    fi


    show_ss_current_config

    echo "$LINE_BOX"
    echo -e "[1] 显示连接信息"
    echo -e "[2] 更新Gost Docker镜像"
    echo -e "[3] 修改SS端口"
    echo -e "[4] 重新生成SS密码"
    echo -e "[5] 修改加密方式"
    echo -e "[6] 查看服务日志"
    echo -e "[7] 重启服务"
    echo -e "[8] 停止服务"
    echo -e "[0] 返回上级菜单"
    echo "$LINE_BOX"
    read -e -p "请选择操作 [0-8]: " ss_choice


    if [[ -z "$ss_choice" ]]; then
      break
    fi

    case "$ss_choice" in
      1) show_ss_connection_info ;;
      2) update_gost_docker ;;
      3) modify_ss_port ;;
      4) regenerate_ss_password ;;
      5) modify_ss_encryption ;;
      6) show_ss_logs ;;
      7) restart_ss_service ;;
      8) stop_ss_service ;;
      0) break ;;
      *) echo -e "无效选项，请重新选择"; sleep 1 ;;
    esac

    [ "$ss_choice" != "6" ] && pause_with_prompt && sleep 1
  done
}



show_xray_connection_info() {
  local config_file="$1"
  local container_name="$2"
  local ip port uuid sni pbk sid

  ip=$(get_public_ip)
  port=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]\+' "$config_file" | grep -o '[0-9]\+')
  uuid=$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
  sni=$(grep -o '"serverNames"[[:space:]]*:[[:space:]]*\["[^"]*"' "$config_file" | sed -n 's/.*\["\([^"]*\)"/\1/p' | head -n1)
  sid=$(grep -o '"shortIds"[[:space:]]*:[[:space:]]*\["[^"]*"' "$config_file" | sed -n 's/.*\["\([^"]*\)"/\1/p' | head -n1)
  pbk="MIwVa4SS-dxn6amHA_a3rN2OyHsUu1N_jaC-k-aHUGk"

  echo ""
  echo "$LINE_BOX"
  echo -e "${XRAY_LABEL} 连接信息"
  echo "$LINE_BOX"
  echo -e "服务器地址: ${ip}"
  echo -e "端口: ${port}"
  echo -e "UUID: ${uuid}"
  echo -e "公钥: ${pbk}"
  echo -e "SNI: ${sni}"
  echo -e "ShortID: ${sid}"
  echo -e "流控: xtls-rprx-vision"
  echo -e "传输协议: tcp"
  echo -e "安全类型: reality"
  echo "$LINE_BOX"
  local link="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&type=tcp&headerType=none#Xray-Reality"
  printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
  printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
}

update_xray_docker() {
  local container_name="$1"
  echo ""
  echo -e "正在更新 Xray Docker 镜像..."
  docker stop "$container_name" 2>/dev/null || true
  docker pull ghcr.io/xtls/xray-core:latest
  docker start "$container_name" 2>/dev/null || {
    echo -e "容器启动失败，尝试重新创建..."
    install_xray_reality
  }
  echo -e "Docker 镜像更新完成"
}

modify_xray_port() {
  local config_file="$1"
  local container_name="$2"

  echo ""
  read -e -p "请输入新端口 (1-65535): " new_port
  if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "端口无效"
    return
  fi

  if ! is_port_free "$new_port"; then
    echo -e "端口 ${new_port} 已被占用"
    return
  fi


  sed -i "s/\"port\"[[:space:]]*:[[:space:]]*[0-9]*/\"port\": ${new_port}/g" "$config_file"


  docker rm -f "$container_name" 2>/dev/null || true
  docker run -d --name "$container_name" --network host --restart unless-stopped \
    -v "$config_file":/data/config.json ghcr.io/xtls/xray-core:latest run -c /data/config.json

  echo -e "端口已修改为: ${new_port}"
}

regenerate_xray_uuid() {
  local config_file="$1"
  local container_name="$2"

  echo ""
  local new_uuid
  new_uuid=$(generate_uuid)


  sed -i "s/\"id\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"id\": \"${new_uuid}\"/g" "$config_file"


  docker restart "$container_name"

  echo -e "UUID 已重新生成: ${new_uuid}"
}

modify_xray_sni() {
  local config_file="$1"
  local container_name="$2"

  echo ""
  echo -e "常用 SNI 域名:"
  echo -e "[1] www.apple.com"
  echo -e "[2] www.cloudflare.com"
  echo -e "[3] www.microsoft.com"
  echo -e "[4] aws.amazon.com"
  echo -e "[5] cdnjs.com"
  echo -e "[6] www.freecodecamp.org"
  echo -e "[7] www.tutorialspoint.com"
  echo -e "[8] www.geeksforgeeks.org"
  echo -e "[9] www.programiz.com"
  echo -e "[10] www.jsdelivr.com"
  echo -e "[11] 自定义域名"

  read -e -p "请选择 [1-11]: " sni_choice

  local new_sni
  case "$sni_choice" in
    1) new_sni="www.apple.com" ;;
    2) new_sni="www.cloudflare.com" ;;
    3) new_sni="www.microsoft.com" ;;
    4) new_sni="aws.amazon.com" ;;
    5) new_sni="cdnjs.com" ;;
    6) new_sni="www.freecodecamp.org" ;;
    7) new_sni="www.tutorialspoint.com" ;;
    8) new_sni="www.geeksforgeeks.org" ;;
    9) new_sni="www.programiz.com" ;;
    10) new_sni="www.jsdelivr.com" ;;
    11)
      read -e -p "请输入自定义域名: " new_sni
      if [[ -z "$new_sni" ]]; then
        echo -e "域名不能为空"
        return
      fi
      ;;
    *) echo -e "无效选择"; return ;;
  esac


  sed -i "s/\"dest\"[[:space:]]*:[[:space:]]*\"[^\"]*:443\"/\"dest\": \"${new_sni}:443\"/g" "$config_file"
  sed -i "s/\"serverNames\"[[:space:]]*:[[:space:]]*\[[^]]*\]/\"serverNames\": [\"${new_sni}\"]/g" "$config_file"


  docker restart "$container_name"

  echo -e "SNI 已修改为: ${new_sni}"
}

show_xray_logs() {
  local container_name="$1"
  echo ""
  echo -e "显示 Xray 服务日志 (Ctrl+C 退出):"
  docker logs -f "$container_name"
}

restart_xray_service() {
  local container_name="$1"
  echo ""
  echo -e "正在重启 Xray 服务..."
  docker restart "$container_name"
  echo -e "Xray 服务已重启"
}

stop_xray_service() {
  local container_name="$1"
  echo ""
  echo -e "正在停止 Xray 服务..."
  docker stop "$container_name"
  echo -e "Xray 服务已停止"
}



show_anytls_connection_info() {
  local config_file="$1"

  if [ -f "$config_file" ]; then
    . "$config_file"
    local ip enc
    ip=$(get_public_ip)
    enc=$(url_encode "$PASS")

    echo ""
    echo "$LINE_BOX"
    echo -e "AnyTLS 连接信息"
    echo "$LINE_BOX"
    echo -e "服务器地址: ${ip}:${PORT}"
    echo -e "密码: ${PASS}"
    echo "$LINE_BOX"
    local link="anytls://${enc}@${ip}:${PORT}?security=tls&allowInsecure=1&type=tcp#${ip}"
    printf '\n    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
    printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  else
    echo -e "配置文件不存在"
  fi
}

update_anytls_binary() {
  echo ""
  echo -e "正在更新 AnyTLS 程序..."
  echo -e "功能开发中，请手动重新安装 AnyTLS"
}

modify_anytls_port() {
  local config_file="$1"

  echo ""
  read -e -p "请输入新端口 (1-65535): " new_port
  if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "端口无效"
    return
  fi

  if ! is_port_free "$new_port"; then
    echo -e "端口 ${new_port} 已被占用"
    return
  fi


  sed -i "s/PORT=.*/PORT=${new_port}/g" "$config_file"


  local SERVICE_FILE="/etc/systemd/system/anytls.service"
  if [ -f "$config_file" ]; then
    . "$config_file"
    sed -i "s/-l 0\.0\.0\.0:[0-9]*/-l 0.0.0.0:${new_port}/g" "$SERVICE_FILE"
  fi

  systemctl daemon-reload
  systemctl restart anytls

  echo -e "端口已修改为: ${new_port}"
}

regenerate_anytls_password() {
  local config_file="$1"
  local new_pass

  echo ""
  new_pass=$(generate_random_password)


  sed -i "s/PASS=.*/PASS=${new_pass}/g" "$config_file"


  local SERVICE_FILE="/etc/systemd/system/anytls.service"
  sed -i "s/-p [^ ]*/-p ${new_pass}/g" "$SERVICE_FILE"

  systemctl daemon-reload
  systemctl restart anytls

  echo -e "密码已重新生成: ${new_pass}"
}

show_anytls_logs() {
  local service_name="$1"
  echo ""
  echo -e "显示 AnyTLS 服务日志 (Ctrl+C 退出):"
  journalctl -u "$service_name" -f
}

restart_anytls_service() {
  local service_name="$1"
  echo ""
  echo -e "正在重启 AnyTLS 服务..."
  systemctl restart "$service_name"
  echo -e "AnyTLS 服务已重启"
}

stop_anytls_service() {
  local service_name="$1"
  echo ""
  echo -e "正在停止 AnyTLS 服务..."
  systemctl stop "$service_name"
  echo -e "AnyTLS 服务已停止"
}



show_ss_current_config() {
  local ss_line
  ss_line=$(grep "^ss/" "$raw_conf_path" 2>/dev/null | head -n1)

  if [[ -n "$ss_line" ]]; then
    local pass port encrypt
    pass=$(echo "$ss_line" | cut -d'/' -f2 | cut -d'#' -f1)
    encrypt=$(echo "$ss_line" | cut -d'#' -f2)
    port=$(echo "$ss_line" | cut -d'#' -f3)

    echo -e "当前端口: ${port:-未知}"
    echo -e "当前密码: ${pass:-未知}"
    echo -e "加密方式: ${encrypt:-未知}"
  else
    echo -e "未找到 SS 配置"
  fi
}

show_ss_connection_info() {
  local ss_line ip
  ss_line=$(grep "^ss/" "$raw_conf_path" 2>/dev/null | head -n1)

  if [[ -n "$ss_line" ]]; then
    local pass port encrypt creds b64 tag
    pass=$(echo "$ss_line" | cut -d'/' -f2 | cut -d'#' -f1)
    encrypt=$(echo "$ss_line" | cut -d'#' -f2)
    port=$(echo "$ss_line" | cut -d'#' -f3)
    ip=$(get_public_ip)

    echo ""
    echo "$LINE_BOX"
    echo -e "Shadowsocks 连接信息"
    echo "$LINE_BOX"
    echo -e "服务器地址: ${ip}"
    echo -e "端口: ${port}"
    echo -e "加密方式: ${encrypt}"
    echo -e "密码: ${pass}"
    echo "$LINE_BOX"
    creds="${encrypt}:${pass}"
    b64=$(encode_base64_clean "$creds")
    b64=$(url_encode "$b64")
    tag=$(url_encode "$ip")
    local link="ss://${b64}@${ip}:${port}#${tag}"
    printf '    %b分享链接:%b\n\n%s\n\n' "$C_GREEN" "$C_RESET" "$link"
    printf '   %b节点二维码（海外qrickit.com网址+连接生成）%b\n%s\n\n' "$C_GREEN" "$C_RESET" "https://qrickit.com/api/qr.php?d=$(url_encode "$link")&qrsize=300"
  else
    echo -e "未找到 SS 配置"
  fi
}

update_gost_docker() {
  echo ""
  echo -e "正在更新 Gost Docker 镜像..."
  docker stop anygostgost 2>/dev/null || true
  docker pull "${GOST_IMAGE}"
  docker start anygostgost 2>/dev/null || docker_run_gost
  echo -e "Gost Docker 镜像更新完成"
}

modify_ss_port() {
  echo ""
  read -e -p "请输入新端口 (1-65535): " new_port
  if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "端口无效"
    return
  fi

  if ! is_port_free "$new_port"; then
    echo -e "端口 ${new_port} 已被占用"
    return
  fi


  sed -i "s/^ss\/\([^#]*\)#\([^#]*\)#[0-9]*/ss\/\1#\2#${new_port}/g" "$raw_conf_path"


  regenerate_gost_config

  echo -e "SS 端口已修改为: ${new_port}"
}

regenerate_ss_password() {
  local new_pass
  echo ""
  new_pass=$(generate_random_password)


  sed -i "s/^ss\/[^#]*#\([^#]*\)#\([^#]*\)/ss\/${new_pass}#\1#\2/g" "$raw_conf_path"


  regenerate_gost_config

  echo -e "SS 密码已重新生成: ${new_pass}"
}

modify_ss_encryption() {
  echo ""
  echo -e "请选择加密方式:"
  echo -e "[1] aes-128-gcm"
  echo -e "[2] aes-256-gcm"
  echo -e "[3] chacha20-ietf-poly1305"
  echo -e "[4] chacha20"
  echo -e "[5] rc4-md5"

  read -e -p "请选择 [1-5]: " encrypt_choice

  local new_encrypt
  case "$encrypt_choice" in
    1) new_encrypt="aes-128-gcm" ;;
    2) new_encrypt="aes-256-gcm" ;;
    3) new_encrypt="chacha20-ietf-poly1305" ;;
    4) new_encrypt="chacha20" ;;
    5) new_encrypt="rc4-md5" ;;
    *) echo -e "无效选择"; return ;;
  esac


  sed -i "s/^ss\/\([^#]*\)#[^#]*#\([^#]*\)/ss\/\1#${new_encrypt}#\2/g" "$raw_conf_path"


  regenerate_gost_config

  echo -e "SS 加密方式已修改为: ${new_encrypt}"
}

show_ss_logs() {
  echo ""
  echo -e "显示 Gost (SS) 服务日志 (Ctrl+C 退出):"
  docker logs -f anygostgost
}

restart_ss_service() {
  echo ""
  echo -e "正在重启 SS 服务..."
  regenerate_gost_config
  echo -e "SS 服务已重启"
}

stop_ss_service() {
  echo ""
  echo -e "正在停止 SS 服务..."
  docker stop anygostgost
  echo -e "SS 服务已停止"
}


regenerate_gost_config() {
  ensure_gost_resources
  if guard_gost; then
    return 0
  fi

  rm -f "$gost_conf_path"
  touch "$gost_conf_path"
  confstart
  writeconf
  conflast
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^anygostgost$'; then
    if ! docker restart anygostgost 2>/dev/null; then
      show_info "原有 GOST 容器重启失败，尝试重新创建..."
      docker rm -f anygostgost 2>/dev/null || true
      docker_run_gost
    fi
  else
    docker_run_gost
  fi
  return 0
}


docker_run_gost() {

  if guard_gost; then
    return
  fi

  if ! docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "^${GOST_IMAGE}$"; then
    docker pull "${GOST_IMAGE}" >/dev/null 2>&1 || docker pull "${GOST_IMAGE}"
  fi

  local run_output
  if ! run_output=$(docker run -d --name anygostgost --network host --restart=always \
    -v "${gost_conf_path}:/gost/config.json" \
    "${GOST_IMAGE}" -C /gost/config.json 2>&1); then
    show_error "GOST 容器启动失败"
    show_info "$run_output"
    return 1
  fi

  return 0
}

Install_ct() {
  check_root
  check_nor_file
  install_deps
  check_file
  check_sys

  # 自动安装 Docker 和 GOST 镜像
  if ! auto_install_docker_and_gost; then
    pause_with_prompt "按回车返回主菜单..."
    return 1
  fi


  ensure_workdir
  if [ ! -f "$gost_conf_path" ]; then
    echo -e "$config_json_content" > "$gost_conf_path"
    chmod 777 "$gost_conf_path"
  fi
  local container_exists=false
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^anygostgost$'; then
    container_exists=true
    show_info "检测到已有 GOST 服务，重载配置后重启..."
  fi
  local image_exists=false
  if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "^${GOST_IMAGE}$"; then
    image_exists=true
  fi

  if [ "$container_exists" = true ]; then
    if ! docker restart anygostgost 2>/dev/null; then
      show_info "原有 GOST 容器重启失败，尝试重新创建..."
      docker rm -f anygostgost 2>/dev/null || true
      if [ "$image_exists" = false ]; then
        docker pull "${GOST_IMAGE}"
        image_exists=true
      fi
      docker_run_gost
    fi
  else
    docker rm -f anygostgost 2>/dev/null || true
    if [ "$image_exists" = false ]; then
      docker pull "${GOST_IMAGE}"
      image_exists=true
    fi
    docker_run_gost
  fi
  echo "$LINE_LIGHT"
  if docker ps --format '{{.Names}}' | grep -q '^anygostgost$'; then
    echo "gost安装成功"
    rm -rf "$(pwd)"/gost
    rm -rf "$(pwd)"/gost.service
    rm -rf "$(pwd)"/config.json
  else
    echo "gost没有安装成功"
    rm -rf "$(pwd)"/gost
    rm -rf "$(pwd)"/gost.service
    rm -rf "$(pwd)"/config.json
  fi
}

Uninstall_ct() {
  docker rm -f anygostgost 2>/dev/null || true

  echo "gost已经成功删除"
}

Start_ct() {

  if guard_gost; then
    echo "GOST配置为空，无法启动服务"
    return
  fi
  docker start anygostgost || docker_run_gost
  echo "已启动"
}

Stop_ct() {
  docker stop anygostgost || true
  echo "已停止"
}

Restart_ct() {
  if regenerate_gost_config; then
    echo "已重读配置并重启"
  else
    show_error "GOST 容器启动失败"
  fi
}

read_protocol() {
  show_menu_title "转发规则类型选择"
  show_option "1" "建立TCP+UDP纯端口转发"
  show_info "本机端口转发到落地机，因为无加密，出境需要协议自带新机密机制"
  echo
  show_option "2" "建立TLS隧道（发送端）"
  show_info "本机建立GOST-TLS隧道加密发包到落地机，需落地机执行解密↓"
  echo
  show_option "3" "建立TLS隧道（接收端）"
  show_info "落地机解密GOST-TLS隧道"
  echo
  read -p "请选择 [1-3]: " numprotocol


  if [[ -z "$numprotocol" ]]; then
    return 1
  elif [ "$numprotocol" == "1" ]; then
    flag_a="nonencrypt"
  elif [ "$numprotocol" == "2" ]; then
    encrypt
  elif [ "$numprotocol" == "3" ]; then
    decrypt
  else
    echo "type error, please try again"
    return 1
  fi
}

read_s_port() {
  echo -e "$LINE_TABLE"
  echo -e "请输入本机监听端口（此端口接收的流量将被转发）"
  echo
  read -e -p "监听端口 [1-65535]: " flag_b

  if [[ -z "$flag_b" ]]; then
    show_error "端口不能为空"
    return 1
  fi

  # 验证端口是否有效
  if [[ ! "$flag_b" =~ ^[0-9]+$ ]] || [ "$flag_b" -lt 1 ] || [ "$flag_b" -gt 65535 ]; then
    show_error "端口无效，请输入 1-65535 之间的数字"
    return 1
  fi
}

read_d_ip() {
  echo -e "$LINE_TABLE"
  echo -e "请输入目标IP地址或域名（端口${flag_b}的流量将转发到此地址）"
  echo
  show_info "常见选择："
  show_info "  • 127.0.0.1 - 转发到本机（默认，直接回车）"
  show_info "  • 远程IP/域名 - 转发到其他服务器"
  echo
  read -e -p "目标地址 [默认: 127.0.0.1]: " flag_c

  # 如果为空则使用默认值 127.0.0.1
  if [[ -z "$flag_c" ]]; then
    flag_c="127.0.0.1"
    show_success "已设置目标地址为: ${flag_c}"
  fi
}

read_d_port() {
  echo -e "$LINE_TABLE"
  echo -e "请输入目标端口（${flag_b} → ${flag_c}:目标端口）"
  echo
  read -e -p "目标端口 [1-65535]: " flag_d

  if [[ -z "$flag_d" ]]; then
    show_error "端口不能为空"
    return 1
  fi

  # 验证端口是否有效
  if [[ ! "$flag_d" =~ ^[0-9]+$ ]] || [ "$flag_d" -lt 1 ] || [ "$flag_d" -gt 65535 ]; then
    show_error "端口无效，请输入 1-65535 之间的数字"
    return 1
  fi
}

writerawconf() {
  ensure_gost_resources
  echo $flag_a"/""$flag_b""#""$flag_c""#""$flag_d" >>"$raw_conf_path"
}

rawconf() {
  ensure_gost_resources
  read_protocol

  if [ $? -ne 0 ]; then
    return 1
  fi
  read_s_port
  if [ $? -ne 0 ]; then
    return 1
  fi
  read_d_ip
  if [ $? -ne 0 ]; then
    return 1
  fi
  read_d_port
  if [ $? -ne 0 ]; then
    return 1
  fi
  writerawconf
  return 0
}

eachconf_retrieve() {
  if [[ "$trans_conf" =~ ^ss/ ]]; then
    flag_s_port=${trans_conf%%#*}
    is_encrypt=${flag_s_port%/*}
    ss_password=${flag_s_port#*/}
    temp_conf=${trans_conf#*#}
    ss_method=${temp_conf%%#*}
    s_port=${temp_conf#*#}
    d_ip=""
    d_port=""
  else
    d_server=${trans_conf#*#}
    d_port=${d_server#*#}
    d_ip=${d_server%#*}
    flag_s_port=${trans_conf%%#*}
    s_port=${flag_s_port#*/}
    is_encrypt=${flag_s_port%/*}
  fi
}

confstart() {
  echo "{
    \"Debug\": true,
    \"Retries\": 0,
    \"ServeNodes\": [" >>$gost_conf_path
}

multiconfstart() {
  echo "        {
            \"Retries\": 0,
            \"ServeNodes\": [" >>$gost_conf_path
}

conflast() {
  echo "    ]
}" >>$gost_conf_path
}

multiconflast() {
  if [ $i -eq $count_line ]; then
    echo "            ]
        }" >>$gost_conf_path
  else
    echo "            ]
        }," >>$gost_conf_path
  fi
}

encrypt() {

    flag_a="encrypttls"
}


decrypt() {

    flag_a="decrypttls"
}

method() {
  if [ $i -eq 1 ]; then
    if [ "$is_encrypt" == "nonencrypt" ]; then
      echo "        \"tcp://:$s_port/$d_ip:$d_port\",
        \"udp://:$s_port/$d_ip:$d_port\"" >>$gost_conf_path
    elif [ "$is_encrypt" == "encrypttls" ]; then
      echo "        \"tcp://:$s_port\",
        \"udp://:$s_port\"
    ],
    \"ChainNodes\": [
        \"relay+tls://$d_ip:$d_port\"" >>$gost_conf_path
    elif [ "$is_encrypt" == "decrypttls" ]; then
        echo "        \"relay+tls://:$s_port/$d_ip:$d_port\"" >>$gost_conf_path
    elif [ "$is_encrypt" == "ss" ]; then
        echo "        \"ss://$ss_method:$ss_password@:$s_port\"" >>$gost_conf_path
    else
      return 0
    fi
  elif [ $i -gt 1 ]; then
    if [ "$is_encrypt" == "nonencrypt" ]; then
      echo "                \"tcp://:$s_port/$d_ip:$d_port\",
                \"udp://:$s_port/$d_ip:$d_port\"" >>$gost_conf_path
    elif [ "$is_encrypt" == "encrypttls" ]; then
      echo "                \"tcp://:$s_port\",
                \"udp://:$s_port\"
            ],
            \"ChainNodes\": [
                \"relay+tls://$d_ip:$d_port\"" >>$gost_conf_path
    elif [ "$is_encrypt" == "decrypttls" ]; then
        echo "        		  \"relay+tls://:$s_port/$d_ip:$d_port\"" >>$gost_conf_path
    elif [ "$is_encrypt" == "ss" ]; then
        echo "                \"ss://$ss_method:$ss_password@:$s_port\"" >>$gost_conf_path
    else
      return 0
    fi
  else
    return 0
  fi
}

writeconf() {
  count_line=$(awk 'END{print NR}' "$raw_conf_path")
  count_line=${count_line:-0}
  for ((i = 1; i <= count_line; i++)); do
    if [ $i -eq 1 ]; then
      trans_conf=$(sed -n "${i}p" "$raw_conf_path")
      if [[ -z "$trans_conf" || "$trans_conf" != */*#*#* ]]; then
        continue
      fi
      eachconf_retrieve
      method
    elif [ $i -gt 1 ]; then
      if [ $i -eq 2 ]; then
        echo "    ],
    \"Routes\": [" >>$gost_conf_path
        trans_conf=$(sed -n "${i}p" "$raw_conf_path")
        if [[ -z "$trans_conf" || "$trans_conf" != */*#*#* ]]; then
          continue
        fi
        eachconf_retrieve
        multiconfstart
        method
        multiconflast
      else
        trans_conf=$(sed -n "${i}p" "$raw_conf_path")
        if [[ -z "$trans_conf" || "$trans_conf" != */*#*#* ]]; then
          continue
        fi
        eachconf_retrieve
        multiconfstart
        method
        multiconflast
      fi
    fi
  done
}

show_all_conf() {
  ensure_gost_resources
  local width_index=4 width_method=12 width_port=8
  local header_index header_method header_port
  header_index=$(pad_cell "序号" "$width_index" center)
  header_method=$(pad_cell "方法" "$width_method" center)
  header_port=$(pad_cell "本机端口" "$width_port" center)
  printf '  %s │ %s │ %s │   %s\n' "$header_index" "$header_method" "$header_port" "发送到的地址和端口"
  printf '  %s\n' "$LINE_TABLE"

  if [ ! -f "$raw_conf_path" ]; then
    echo -e "暂无转发配置记录"
    return 1
  fi

  local count_line has_entries=false
  count_line=$(awk 'END{print NR}' "$raw_conf_path")

  for ((i = 1; i <= count_line; i++)); do
    trans_conf=$(sed -n "${i}p" "$raw_conf_path")
    if [[ -z "$trans_conf" || "$trans_conf" != */*#*#* ]]; then
      continue
    fi

    eachconf_retrieve
    has_entries=true

    local method_label target_info
    case "$is_encrypt" in
      "nonencrypt")
        method_label="不加密中转"
        target_info="${d_ip}:${d_port}"
        ;;
      "encrypttls")
        method_label="加密隧道"
        target_info="${d_ip}:${d_port}"
        ;;
      "decrypttls")
        method_label="隧道解密"
        target_info="${d_ip}:${d_port}"
        ;;
      "ss")
        method_label="ss"
        target_info="加密:${ss_method} 密码:${ss_password}"
        ;;
      *)
        method_label="未知"
        target_info="${d_ip}:${d_port}"
        ;;
    esac

    local display_port="${s_port:--}"
    local col_index col_method col_port
    col_index=$(pad_cell "$i" "$width_index" center)
    col_method=$(pad_cell "$method_label" "$width_method" center)
    col_port=$(pad_cell "$display_port" "$width_port" center)
    printf '  %s │ %s │ %s │ %s\n' "$col_index" "$col_method" "$col_port" "$target_info"
    printf '  %s\n' "$LINE_TABLE"
  done

  if [ "$has_entries" = false ]; then
    echo -e "暂无转发配置记录"
    return 1
  fi

  return 0
}

add_forwarding_rule_menu() {
  show_menu_title "新增转发规则"
  show_info "根据提示选择转发类型并填写端口、目标信息。"
  show_info "提示: 在任一步骤直接回车即可取消并返回上级菜单。"
  echo

  if rawconf; then
    if regenerate_gost_config; then
      show_success "转发配置已生效！当前配置如下："
    else
      show_error "配置已更新，但 GOST 容器启动失败，请根据提示排查。"
    fi
    show_all_conf
    echo
    pause_with_prompt "按回车返回主菜单..."
  fi
}

delete_forwarding_rule() {
  ensure_gost_resources
  local index="$1"

  local target_line
  target_line=$(sed -n "${index}p" "$raw_conf_path")
  if [[ -z "$target_line" || "$target_line" != */*#*#* ]]; then
    show_error "编号 ${index} 无效或条目不存在。"
    return 1
  fi

  sed -i "${index}d" "$raw_conf_path"
  if regenerate_gost_config; then
    show_success "配置已删除，GOST 服务已自动重载。"
  else
    show_error "已删除配置，但 GOST 容器启动失败，请根据提示排查。"
  fi
  return 0
}


# 检查 Docker 和 GOST 镜像状态（静默）
check_docker_and_image_status() {
  local docker_status="未安装"
  local gost_image_status="未下载"

  # 检查 Docker
  if command -v docker >/dev/null 2>&1; then
    if systemctl is-active --quiet docker 2>/dev/null || docker ps >/dev/null 2>&1; then
      docker_status="${C_GREEN}运行中${C_RESET}"
    else
      docker_status="${C_RED}已安装但未运行${C_RESET}"
    fi
  else
    docker_status="${C_RED}未安装${C_RESET}"
  fi

  # 检查 GOST 镜像
  if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "^${GOST_IMAGE}$"; then
    gost_image_status="${C_GREEN}已下载${C_RESET}"
  else
    gost_image_status="${C_RED}未下载${C_RESET}"
  fi

  echo -e "  Docker: ${docker_status}  |  GOST镜像: ${gost_image_status}"
}

# 自动安装缺失组件（仅在需要时调用）
auto_install_docker_and_gost() {
  # 检查并安装 Docker
  if ! command -v docker >/dev/null 2>&1; then
    show_info "未检测到 Docker，正在自动安装..."
    ensure_docker
    if ! command -v docker >/dev/null 2>&1; then
      show_error "Docker 安装失败，请手动安装后再运行脚本"
      return 1
    fi
    show_success "Docker 安装完成"
  fi

  # 确保 Docker 服务运行
  if ! systemctl is-active --quiet docker 2>/dev/null && ! docker ps >/dev/null 2>&1; then
    show_info "正在启动 Docker 服务..."
    systemctl start docker 2>/dev/null || true
    sleep 2
  fi

  # 检查并下载 GOST 镜像
  if ! docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "^${GOST_IMAGE}$"; then
    show_info "未检测到 GOST 镜像，正在自动下载..."
    if docker pull "${GOST_IMAGE}"; then
      show_success "GOST 镜像下载完成"
    else
      show_error "GOST 镜像下载失败，请检查网络连接"
      return 1
    fi
  fi

  return 0
}

while true; do
  clear
  echo
  printf '  %b\n' "${C_GREEN}Anygost 一键纯净搭建 Reality/AnyTLS/GOST 服务端${C_RESET}"
  echo "  配置文件路径: /root/net-tools-anygost/"
  echo "  项目地址: https://github.com/vince-ankunding/anygost"
  show_services_status

  show_menu_title "服务部署与管理"
  show_option "1" "搭建服务端"
  show_option "2" "服务配置与管理"
  show_option "3" "服务端卸载清理"

  show_menu_title "GOST 服务控制"
  show_option "4" "启动 GOST 服务"
  show_option "5" "停止 GOST 服务"
  show_option "6" "重启 GOST 服务"

  show_menu_title "转发配置管理"
  show_option "7" "新增转发规则"
  show_option "9" "查看/删除配置"

  echo
  read -e -p "请选择 [1-9]: " num


  if [[ -z "$num" ]]; then
    continue
  fi

  case "$num" in
  1)
    build_server_menu
    ;;
  2)
    service_management_menu
    ;;
  3)

    show_menu_title "服务卸载"
    echo -e "${C_RED}警告: 卸载操作将完全删除所选服务及其配置文件${C_RESET}"
    echo
    show_option "1" "卸载 ${XRAY_LABEL}"
    show_option "2" "卸载 AnyTLS 服务"
    show_option "3" "卸载 GOST 代理服务"


    if [ -f "$raw_conf_path" ] && grep -q "^ss/" "$raw_conf_path" 2>/dev/null; then
      show_option "4" "删除 SS 服务端"
    fi

    echo
    show_option "9" "一键删除本脚本的全部服务端和配置文件"
    echo
    read -e -p "请选择要卸载的服务 [1-4/9]: " un_num


    if [[ -z "$un_num" ]]; then
      continue
    fi

    case "$un_num" in
      9)
        docker rm -f anygostxray 2>/dev/null || true
        rm -f /root/net-tools-anygost/xray-config.json || true
        systemctl stop anytls 2>/dev/null || true
        systemctl disable anytls 2>/dev/null || true
        rm -f /etc/systemd/system/anytls.service 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        rm -f /usr/local/bin/anytls-server /usr/local/bin/anytls-client 2>/dev/null || true
        rm -f /root/net-tools-anygost/anytls-config.json 2>/dev/null || true
        Uninstall_ct
        rm -f "$gost_conf_path" "$raw_conf_path"
        rm -rf "$WORKDIR"
        echo
        show_success "全部服务端及配置文件已卸载"
        ;;
      1)
        docker rm -f anygostxray 2>/dev/null || true
        rm -f /root/net-tools-anygost/xray-config.json || true
        echo
        show_success "${XRAY_LABEL} 服务已卸载"
        ;;
      2)
        systemctl stop anytls 2>/dev/null || true
        systemctl disable anytls 2>/dev/null || true
        rm -f /etc/systemd/system/anytls.service 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        rm -f /usr/local/bin/anytls-server /usr/local/bin/anytls-client 2>/dev/null || true
        rm -f /root/net-tools-anygost/anytls-config.json 2>/dev/null || true
        echo
        show_success "AnyTLS 服务已卸载"
        ;;
      3)
        Uninstall_ct
        ;;
      4)

        if [ -f "$raw_conf_path" ] && grep -q "^ss/" "$raw_conf_path" 2>/dev/null; then
          sed -i '/^ss\//d' "$raw_conf_path"
          echo
          show_success "SS 服务端配置已删除"

          regenerate_gost_config
        else
          show_error "未找到 SS 服务端配置"
        fi
        ;;
      *)
        show_error "无效选择"
        ;;
    esac
    echo
    pause_with_prompt
    ;;
  4)
    Start_ct
    echo
    pause_with_prompt
    ;;
  5)
    Stop_ct
    echo
    pause_with_prompt
    ;;
  6)
    Restart_ct
    echo
    pause_with_prompt
    ;;
  7)
    add_forwarding_rule_menu
    ;;
  9)
    if ! show_all_conf; then
      echo
      pause_with_prompt "按回车返回主菜单..."
      continue
    fi

    read -e -p "请输入你要删除的配置编号：" numdelete

    if [[ -z "$numdelete" ]]; then
      continue
    fi

    if [[ "$numdelete" =~ ^[0-9]+$ ]]; then
      if delete_forwarding_rule "$numdelete"; then
        echo
        pause_with_prompt "按回车返回主菜单..."
      else
        echo
        pause_with_prompt "按回车返回主菜单..."
      fi
    else
      show_error "请输入正确的数字编号。"
      echo
      pause_with_prompt "按回车返回主菜单..."
    fi
    ;;
   *)
    show_error "输入无效，请选择 [1-9]"
    echo
    pause_with_prompt
    ;;
  esac
done
