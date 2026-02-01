#!/bin/bash

# ==============================
# Backhaul Manager Script
# ==============================

SERVICE="backhaul"
BIN="/usr/local/bin/backhaul"
CONFIG_DIR="/opt/backhaul"
CONFIG="$CONFIG_DIR/config.toml"
SERVICE_FILE="/etc/systemd/system/backhaul.service"
REPO="https://github.com/Musixal/Backhaul"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

require_root() {
  [[ $EUID -ne 0 ]] && echo -e "${RED}Run as root${NC}" && exit 1
}

pause() {
  read -rp "Press Enter to continue..."
}

install_binary() {
  echo "Installing Backhaul..."
  curl -fsSL https://raw.githubusercontent.com/Musixal/Backhaul/main/install.sh | bash
}

create_dirs() {
  mkdir -p $CONFIG_DIR
}

create_tls() {
  mkdir -p $CONFIG_DIR/tls
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout $CONFIG_DIR/tls/key.pem \
    -out $CONFIG_DIR/tls/cert.pem \
    -days 365 \
    -subj "/CN=backhaul"
}

configure() {
  clear
  echo "Backhaul Configuration"
  echo "======================"

  read -rp "Mode (server/client): " MODE
  read -rp "Protocol (tcp/udp/ws/wss): " PROTOCOL
  read -rp "Listen Port: " PORT

  TLS="false"
  if [[ "$PROTOCOL" == "wss" ]]; then
    TLS="true"
    create_tls
  else
    read -rp "Enable TLS? (y/n): " T
    [[ $T == "y" ]] && TLS="true" && create_tls
  fi

  cat > $CONFIG <<EOF
mode = "$MODE"
protocol = "$PROTOCOL"
port = $PORT
tls = $TLS
cert = "$CONFIG_DIR/tls/cert.pem"
key = "$CONFIG_DIR/tls/key.pem"
EOF
}

create_service() {
  cat > $SERVICE_FILE <<EOF
[Unit]
Description=Backhaul Tunnel
After=network.target

[Service]
ExecStart=$BIN -c $CONFIG
Restart=always
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable --now $SERVICE
}

install() {
  require_root
  install_binary
  create_dirs
  configure
  create_service
  echo -e "${GREEN}Backhaul installed successfully.${NC}"
  pause
}

status() {
  systemctl status $SERVICE --no-pager
  pause
}

view_config() {
  clear
  if [[ ! -f $CONFIG ]]; then
    echo -e "${RED}No configuration found.${NC}"
  else
    cat $CONFIG
  fi
  pause
}

view_logs() {
  clear
  echo "Backhaul Logs (Ctrl+C to exit)"
  journalctl -u $SERVICE -f
}

manage() {
  while true; do
    clear
    echo "Manage Backhaul"
    echo "================"
    echo "1) Edit configuration"
    echo "2) View current configuration"
    echo "3) View logs / connection status"
    echo "0) Back"
    read -rp "Select: " C

    case $C in
      1)
        configure
        systemctl restart $SERVICE
        pause
        ;;
      2) view_config ;;
      3) view_logs ;;
      0) break ;;
      *) pause ;;
    esac
  done
}

uninstall() {
  require_root
  systemctl disable --now $SERVICE 2>/dev/null
  rm -f $SERVICE_FILE
  rm -rf $CONFIG_DIR
  rm -f $BIN
  systemctl daemon-reload
  echo -e "${GREEN}Backhaul removed completely.${NC}"
  pause
}

menu() {
  while true; do
    clear
    echo "Backhaul Manager"
    echo "================"
    echo "1) Install"
    echo "2) Manage"
    echo "3) Status"
    echo "4) Uninstall"
    echo "0) Exit"
    read -rp "Choose: " O

    case $O in
      1) install ;;
      2) manage ;;
      3) status ;;
      4) uninstall ;;
      0) exit ;;
      *) pause ;;
    esac
  done
}

menu
