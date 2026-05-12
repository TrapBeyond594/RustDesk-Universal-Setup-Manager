#!/bin/bash

# Универсальный менеджер RustDesk Server
# Поддерживает как Free, так и Pro версии
# Поддерживает Debian/Ubuntu, CentOS/RHEL/Fedora, Arch

TITLE="Универсальный менеджер RustDesk"
RUSTDESK_FREE_DIR="/opt/rustdesk"
RUSTDESK_PRO_DIR="/var/lib/rustdesk-server"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Пожалуйста, запустите от имени root${NC}"
  exit 1
fi

main_menu() {
  while true; do
    CHOICE=$(whiptail --title "$TITLE" --menu "Выберите действие:" 20 70 10 \
      "1" "Установить RustDesk Server (Бесплатная)" \
      "2" "Установить RustDesk Server Pro (Про)" \
      "3" "Обновить RustDesk (Проверка версий)" \
      "4" "Обновить систему (OS Update)" \
      "5" "Расширенные инструменты (Утилиты)" \
      "6" "Полное удаление (с корнями)" \
      "7" "Выход" 3>&1 1>&2 2>&3)

    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    case $CHOICE in
      1) install_free ;;
      2) install_pro ;;
      3) check_for_updates ;;
      4) update_system ;;
      5) "$SCRIPT_DIR/rustdesk-utils.sh" ;;
      6) full_uninstall ;;
      7) exit 0 ;;
      *) exit 0 ;;
    esac
  done
}

# Заглушки функций (будут реализованы в следующих шагах)
get_server_address() {
  local ADDR
  while true; do
    ADDR=$(whiptail --title "Настройка адреса" --inputbox "Введите IP-адрес, DDNS или домен вашего сервера (например, 1.2.3.4 или rustdesk.example.com):" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$ADDR" ]; then
      whiptail --msgbox "Адрес не может быть пустым!" 8 40
      continue
    fi
    # Базовая валидация (домен или IP)
    if [[ "$ADDR" =~ ^[a-zA-Z0-9.-]+$ ]]; then
      echo "$ADDR"
      return 0
    else
      whiptail --msgbox "Неверный формат адреса!" 8 40
    fi
  done
}

install_free() {
  if (whiptail --title "$TITLE" --yesno "Установить бесплатную версию RustDesk Server?" 10 60); then
    SERVER_ADDR=$(get_server_address)
    echo -e "${CYAN}Запуск установки бесплатной версии...${NC}"

    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64)  FILE_ARCH="amd64" ;;
      aarch64) FILE_ARCH="arm64v8" ;;
      armv7l)  FILE_ARCH="armv7" ;;
      i386|i686) FILE_ARCH="i386" ;;
      *) echo -e "${RED}Неподдерживаемая архитектура: $ARCH${NC}"; return 1 ;;
    esac

    LATEST_FREE=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    DOWNLOAD_URL="https://github.com/rustdesk/rustdesk-server/releases/download/${LATEST_FREE}/rustdesk-server-linux-${FILE_ARCH}.zip"

    mkdir -p "$RUSTDESK_FREE_DIR"
    mkdir -p "/var/log/rustdesk"
    cd "$RUSTDESK_FREE_DIR" || return 1

    echo -e "${CYAN}Скачивание ${DOWNLOAD_URL}...${NC}"
    wget "$DOWNLOAD_URL" -O rustdesk-server.zip
    unzip -o rustdesk-server.zip

    # В zip архивах бинарники обычно лежат в подпапке (например amd64/)
    if [ -d "amd64" ]; then mv amd64/* .; rm -rf amd64; fi
    if [ -d "arm64v8" ]; then mv arm64v8/* .; rm -rf arm64v8; fi
    if [ -d "armv7" ]; then mv armv7/* .; rm -rf armv7; fi
    if [ -d "i386" ]; then mv i386/* .; rm -rf i386; fi

    chmod +x hbbs hbbr

    # Systemd hbbs
    cat << EOF > /etc/systemd/system/rustdesksignal.service
[Unit]
Description=RustDesk Signal Server (Free)
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=${RUSTDESK_FREE_DIR}/hbbs
WorkingDirectory=${RUSTDESK_FREE_DIR}
Restart=always
StandardOutput=append:/var/log/rustdesk/signalserver.log
StandardError=append:/var/log/rustdesk/signalserver.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Systemd hbbr
    cat << EOF > /etc/systemd/system/rustdeskrelay.service
[Unit]
Description=RustDesk Relay Server (Free)
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=${RUSTDESK_FREE_DIR}/hbbr
WorkingDirectory=${RUSTDESK_FREE_DIR}
Restart=always
StandardOutput=append:/var/log/rustdesk/relayserver.log
StandardError=append:/var/log/rustdesk/relayserver.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable rustdesksignal.service rustdeskrelay.service
    systemctl start rustdesksignal.service rustdeskrelay.service

    echo "$SERVER_ADDR" > "$RUSTDESK_FREE_DIR/address.conf"

    rm rustdesk-server.zip
    whiptail --title "$TITLE" --msgbox "Установка бесплатной версии завершена.\nАдрес: $SERVER_ADDR\nДиректория: $RUSTDESK_FREE_DIR\nЛоги: /var/log/rustdesk/" 12 60
  fi
}

install_pro() {
  if (whiptail --title "$TITLE" --yesno "Установить RustDesk Server Pro?" 10 60); then
    SERVER_ADDR=$(get_server_address)
    echo -e "${CYAN}Запуск установки Pro версии...${NC}"

    ARCH=$(uname -m)
    TLS=""
    if command -v ldconfig &> /dev/null; then
        if ldconfig -p | grep -q "libssl.so.3"; then
            TLS="-nativetls"
        fi
    fi

    case "$ARCH" in
      x86_64)  FILE_ARCH="amd64" ;;
      aarch64) FILE_ARCH="arm64v8" ;;
      armv7l)  FILE_ARCH="armv7" ;;
      i386|i686) FILE_ARCH="i386" ;;
      *) echo -e "${RED}Неподдерживаемая архитектура: $ARCH${NC}"; return 1 ;;
    esac

    LATEST_PRO=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    DOWNLOAD_URL="https://github.com/rustdesk/rustdesk-server-pro/releases/download/${LATEST_PRO}/rustdesk-server-linux-${FILE_ARCH}${TLS}.tar.gz"

    mkdir -p "$RUSTDESK_PRO_DIR"
    mkdir -p "/var/log/rustdesk-server"
    cd "$RUSTDESK_PRO_DIR" || return 1

    echo -e "${CYAN}Скачивание ${DOWNLOAD_URL}...${NC}"
    if ! wget "$DOWNLOAD_URL" -O rustdesk-server-pro.tar.gz; then
       # Если с nativetls не нашлось, пробуем без него
       if [ -n "$TLS" ]; then
         echo -e "${CYAN}Попытка скачивания без nativetls...${NC}"
         DOWNLOAD_URL="https://github.com/rustdesk/rustdesk-server-pro/releases/download/${LATEST_PRO}/rustdesk-server-linux-${FILE_ARCH}.tar.gz"
         wget "$DOWNLOAD_URL" -O rustdesk-server-pro.tar.gz || return 1
       else
         return 1
       fi
    fi

    tar -xzf rustdesk-server-pro.tar.gz

    # В tar.gz обычно папка с тем же именем, что и в архиве (например rustdesk-server-linux-amd64/)
    DIR_NAME=$(tar -tf rustdesk-server-pro.tar.gz | head -1 | cut -f1 -d"/")
    mv "$DIR_NAME"/* .
    rm -rf "$DIR_NAME"

    chmod +x hbbs hbbr rustdesk-utils
    cp hbbs hbbr rustdesk-utils /usr/bin/

    # Systemd hbbs
    cat << EOF > /etc/systemd/system/rustdesk-hbbs.service
[Unit]
Description=RustDesk Signal Server (Pro)
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbs
WorkingDirectory=${RUSTDESK_PRO_DIR}
Restart=always
StandardOutput=append:/var/log/rustdesk-server/hbbs.log
StandardError=append:/var/log/rustdesk-server/hbbs.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Systemd hbbr
    cat << EOF > /etc/systemd/system/rustdesk-hbbr.service
[Unit]
Description=RustDesk Relay Server (Pro)
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/bin/hbbr
WorkingDirectory=${RUSTDESK_PRO_DIR}
Restart=always
StandardOutput=append:/var/log/rustdesk-server/hbbr.log
StandardError=append:/var/log/rustdesk-server/hbbr.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable rustdesk-hbbs.service rustdesk-hbbr.service
    systemctl start rustdesk-hbbs.service rustdesk-hbbr.service

    echo "$SERVER_ADDR" > "$RUSTDESK_PRO_DIR/address.conf"

    rm rustdesk-server-pro.tar.gz
    whiptail --title "$TITLE" --msgbox "Установка Pro версии завершена.\nАдрес: $SERVER_ADDR\nДиректория: $RUSTDESK_PRO_DIR\nБинарники в /usr/bin/\nЛоги: /var/log/rustdesk-server/" 12 60
  fi
}
update_system() {
  echo -e "${CYAN}Обновление системы...${NC}"
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"debian"* ]]; then
    apt-get update && apt-get upgrade -y
  elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" || "$OS_ID" == "fedora" || "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* ]]; then
    if command -v dnf &> /dev/null; then
      dnf update -y
    else
      yum update -y
    fi
  elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
    pacman -Syu --noconfirm
  fi
  whiptail --title "$TITLE" --msgbox "Обновление системы завершено." 8 40
}

check_for_updates() {
  echo -e "${CYAN}Проверка обновлений RustDesk Server...${NC}"

  # Получение текущих версий (если установлены)
  CUR_FREE="Не установлена"
  [ -f "$RUSTDESK_FREE_DIR/hbbs" ] && CUR_FREE=$("$RUSTDESK_FREE_DIR/hbbs" -v 2>&1 | head -n 1 | awk '{print $NF}')

  CUR_PRO="Не установлена"
  [ -x "/usr/bin/hbbs" ] && [ -d "$RUSTDESK_PRO_DIR" ] && CUR_PRO=$(/usr/bin/hbbs -v 2>&1 | head -n 1 | awk '{print $NF}')

  LATEST_FREE=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  LATEST_PRO=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

  whiptail --title "$TITLE - Обновления" --msgbox "Версии RustDesk Server:\n\nБесплатная:\n- Текущая: $CUR_FREE\n- Доступна: $LATEST_FREE\n\nPro версия:\n- Текущая: $CUR_PRO\n- Доступна: $LATEST_PRO\n\nДля обновления выберите соответствующий пункт установки в главном меню." 15 65
}
full_uninstall() {
  if (whiptail --title "$TITLE" --yesno "ВНИМАНИЕ: Это полностью удалит все версии RustDesk Server и их данные (с корнями). Продолжить?" 12 60); then
    echo -e "${RED}Удаление RustDesk Server...${NC}"

    # Остановка и отключение служб
    SERVICES=("rustdesk-hbbs" "rustdesk-hbbr" "rustdesksignal" "rustdeskrelay" "gohttpserver")
    for svc in "${SERVICES[@]}"; do
      echo -e "${CYAN}Остановка $svc...${NC}"
      systemctl stop "$svc" 2>/dev/null
      systemctl disable "$svc" 2>/dev/null
      rm -f "/etc/systemd/system/$svc.service"
    done
    systemctl daemon-reload

    # Удаление директорий
    DIRS=(
      "/opt/rustdesk"
      "/var/lib/rustdesk-server"
      "/var/log/rustdesk"
      "/var/log/rustdesk-server"
      "/opt/gohttp"
      "/var/log/gohttp"
    )
    for dir in "${DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo -e "${CYAN}Удаление $dir...${NC}"
        rm -rf "$dir"
      fi
    done

    # Удаление бинарников (если они в /usr/bin)
    rm -f /usr/bin/hbbs /usr/bin/hbbr /usr/bin/rustdesk-utils

    whiptail --title "$TITLE" --msgbox "Полное удаление завершено." 10 60
  fi
}

identify_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_LIKE=$ID_LIKE
  elif [ -f /etc/debian_version ]; then
    OS_ID="debian"
  elif [ -f /etc/redhat-release ]; then
    OS_ID="rhel"
  elif [ -f /etc/arch-release ]; then
    OS_ID="arch"
  else
    OS_ID=$(uname -s)
  fi
}

install_deps() {
  echo -e "${CYAN}Установка зависимостей...${NC}"
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"debian"* ]]; then
    apt-get update
    apt-get install -y curl wget unzip tar dnsutils whiptail sqlite3
  elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" || "$OS_ID" == "fedora" || "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* ]]; then
    if command -v dnf &> /dev/null; then
      dnf install -y curl wget unzip tar bind-utils whiptail sqlite
    else
      yum install -y curl wget unzip tar bind-utils whiptail sqlite
    fi
  elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
    pacman -Syu --noconfirm
    pacman -S --noconfirm curl wget unzip tar bind whiptail sqlite
  else
    echo -e "${RED}Неподдерживаемая ОС. Попытка продолжить...${NC}"
    sleep 2
  fi
}

# Запуск
identify_os
install_deps
chmod +x rustdesk-utils.sh

main_menu
