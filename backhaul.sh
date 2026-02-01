#!/bin/bash

INSTALL_DIR="/opt/backhaul"
BIN="$INSTALL_DIR/backhaul"
CONFIG="$INSTALL_DIR/config.toml"
SERVICE="backhaul"

GREEN="\e[32m"; RED="\e[31m"; NC="\e[0m"

require_root() {
  [[ $EUID -ne 0 ]] && echo -e "${RED}Run as root${NC}" && exit 1
}

pause() {
  read -rp "Press Enter to continue..."
}

status() {
  echo
  if systemctl is-active --quiet $SERVICE; then
    echo -e "${GREEN}Backhaul is running${NC}"
  else
    echo -e "${RED}Backhaul is not running${NC}"
  fi
  systemctl status $SERVICE --no-pager
  pause
}

write_service() {
cat > /etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=Backhaul Tunnel
After=network.target

[Service]
ExecStart=$BIN -c $CONFIG
Restart=always
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE
systemctl restart $SERVICE
}

configure() {
  mkdir -p $INSTALL_DIR
  cd $INSTALL_DIR || exit 1

  echo "Select mode:"
  select MODE in Server Client; do break; done

  echo "Select transport:"
  select TRANSPORT in tcp ws wss wsmux wssmux; do break; done

  read -rp "Port [3080]: " PORT
  PORT=${PORT:-3080}

  read -rp "Auth token: " TOKEN

  USE_TLS="no"
  if [[ "$TRANSPORT" =~ ^wss ]]; then
    read -rp "Enable TLS? (y/n): " t
    [[ "$t" == "y" ]] && USE_TLS="yes"
  fi

  if [[ "$MODE" == "Server" ]]; then

    if [[ "$USE_TLS" == "yes" ]]; then
      mkdir -p tls
      openssl genpkey -algorithm RSA -out tls/server.key -pkeyopt rsa_keygen_bits:2048
      openssl req -new -key tls/server.key -out tls/server.csr \
        -subj "/C=US/O=Backhaul/CN=Backhaul"
      openssl x509 -req -in tls/server.csr -signkey tls/server.key \
        -out tls/server.crt -days 365
    fi

    echo "Add port forwards (example: 443=80), empty to finish"
    PORTS=()
    while true; do
      read -rp "> " p
      [[ -z "$p" ]] && break
      PORTS+=("\"$p\"")
    done

cat > $CONFIG <<EOF
[server]
bind_addr = "0.0.0.0:$PORT"
transport = "$TRANSPORT"
token = "$TOKEN"
log_level = "info"
EOF

    [[ ${#PORTS[@]} -gt 0 ]] && echo "ports = [${PORTS[*]}]" >> $CONFIG

    [[ "$USE_TLS" == "yes" ]] && cat >> $CONFIG <<EOF
tls_cert = "$INSTALL_DIR/tls/server.crt"
tls_key  = "$INSTALL_DIR/tls/server.key"
EOF

  else
    read -rp "Server address (IP:PORT): " REMOTE
cat > $CONFIG <<EOF
[client]
remote_addr = "$REMOTE"
transport = "$TRANSPORT"
token = "$TOKEN"
log_level = "info"
EOF
  fi
}

install() {
  require_root
  apt update -y
  apt install -y curl wget tar openssl

  mkdir -p $INSTALL_DIR
  cd $INSTALL_DIR || exit 1

  wget -q https://github.com/Musixal/Backhaul/releases/latest/download/backhaul_linux_amd64.tar.gz
  tar -xzf backhaul_linux_amd64.tar.gz
  chmod +x backhaul

  configure
  write_service

  ln -sf "$0" /usr/local/bin/backhaul
  echo -e "${GREEN}Installed successfully${NC}"
  pause
}

manage() {
  require_root
  [[ ! -f $CONFIG ]] && echo "Not installed" && pause && return
  configure
  systemctl restart $SERVICE
  echo -e "${GREEN}Configuration updated${NC}"
  pause
}

restart_service() {
  systemctl restart $SERVICE
  echo -e "${GREEN}Service restarted${NC}"
  pause
}

uninstall() {
  require_root
  systemctl stop $SERVICE 2>/dev/null
  systemctl disable $SERVICE 2>/dev/null
  rm -f /etc/systemd/system/$SERVICE.service
  systemctl daemon-reload
  rm -rf $INSTALL_DIR
  rm -f /usr/local/bin/backhaul
  echo -e "${GREEN}Backhaul completely removed${NC}"
  pause
}

menu() {
  clear
  echo "Backhaul Manager"
  echo "================"
  echo "1) Install"
  echo "2) Manage configuration"
  echo "3) Show status"
  echo "4) Restart service"
  echo "5) Uninstall"
  echo "0) Exit"
  echo
  read -rp "Select option: " CHOICE

  case $CHOICE in
    1) install ;;
    2) manage ;;
    3) status ;;
    4) restart_service ;;
    5) uninstall ;;
    0) exit 0 ;;
    *) echo "Invalid option"; pause ;;
  esac
}

while true; do
  menu
done
