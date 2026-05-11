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
    CHOICE=$(whiptail --title "$TITLE" --menu "Выберите действие:" 18 70 8 \
      "1" "Установить RustDesk Server (Бесплатная версия)" \
      "2" "Установить RustDesk Server Pro (Про версия)" \
      "3" "Обновить систему и проверить обновления RustDesk" \
      "4" "Полное удаление (с корнями)" \
      "5" "Проверить статус служб" \
      "6" "Показать публичный ключ" \
      "9" "Перегенерировать ключи" \
      "7" "Информация о веб-панели (Pro)" \
      "8" "Выход" 3>&1 1>&2 2>&3)

    case $CHOICE in
      1) install_free ;;
      2) install_pro ;;
      3) maintenance_menu ;;
      4) full_uninstall ;;
      5) show_status ;;
      6) show_key ;;
      7) web_info ;;
      9) regenerate_keys ;;
      8) exit 0 ;;
      *) exit 0 ;;
    esac
  done
}

maintenance_menu() {
    update_system
    check_for_updates
    whiptail --title "$TITLE" --msgbox "Техническое обслуживание завершено." 10 60
}

# Заглушки функций (будут реализованы в следующих шагах)
install_free() {
  if (whiptail --title "$TITLE" --yesno "Установить бесплатную версию RustDesk Server?" 10 60); then
    echo -e "${CYAN}Запуск установки бесплатной версии...${NC}"
    wget https://raw.githubusercontent.com/techahold/rustdeskinstall/master/install.sh -O free_install.sh
    chmod +x free_install.sh
    ./free_install.sh
    rm free_install.sh
    whiptail --title "$TITLE" --msgbox "Установка бесплатной версии завершена." 10 60
  fi
}

install_pro() {
  if (whiptail --title "$TITLE" --yesno "Установить RustDesk Server Pro?" 10 60); then
    echo -e "${CYAN}Запуск установки Pro версии...${NC}"
    wget https://raw.githubusercontent.com/rustdesk/rustdesk-server-pro/main/install.sh -O pro_install.sh
    chmod +x pro_install.sh
    ./pro_install.sh
    rm pro_install.sh
    whiptail --title "$TITLE" --msgbox "Установка Pro версии завершена." 10 60
  fi
}
update_system() {
  echo -e "${CYAN}Обновление репозиториев системы...${NC}"
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"debian"* ]]; then
    apt-get update
  elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" || "$OS_ID" == "fedora" || "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* ]]; then
    yum check-update
  elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
    pacman -Sy
  fi
}

check_for_updates() {
  echo -e "${CYAN}Проверка обновлений RustDesk Server...${NC}"
  LATEST_FREE=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  LATEST_PRO=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

  whiptail --title "$TITLE" --msgbox "Последние версии на GitHub:\n\nБесплатная: $LATEST_FREE\nPro: $LATEST_PRO\n\nЕсли ваша версия устарела, просто запустите установку заново для обновления." 12 60
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
show_status() {
  STATUS_HBBS_PRO=$(systemctl is-active rustdesk-hbbs.service 2>/dev/null || echo "не активна")
  STATUS_HBBR_PRO=$(systemctl is-active rustdesk-hbbr.service 2>/dev/null || echo "не активна")
  STATUS_SIGNAL_FREE=$(systemctl is-active rustdesksignal.service 2>/dev/null || echo "не активна")
  STATUS_RELAY_FREE=$(systemctl is-active rustdeskrelay.service 2>/dev/null || echo "не активна")

  whiptail --title "$TITLE" --msgbox "Статус служб:\n\nPro версия:\n- HBBS: $STATUS_HBBS_PRO\n- HBBR: $STATUS_HBBR_PRO\n\nБесплатная версия:\n- Signal: $STATUS_SIGNAL_FREE\n- Relay: $STATUS_RELAY_FREE" 15 65
}

show_key() {
  KEY_PATH=""
  [ -d "$RUSTDESK_PRO_DIR" ] && KEY_PATH=$(find "$RUSTDESK_PRO_DIR" -maxdepth 1 -name "*.pub" | head -n 1)
  [ -z "$KEY_PATH" ] && [ -d "$RUSTDESK_FREE_DIR" ] && KEY_PATH=$(find "$RUSTDESK_FREE_DIR" -maxdepth 1 -name "*.pub" | head -n 1)

  if [ -f "$KEY_PATH" ]; then
    KEY_CONTENT=$(cat "$KEY_PATH")
    whiptail --title "$TITLE" --msgbox "Публичный ключ найден:\n\n$KEY_CONTENT" 12 60
  else
    whiptail --title "$TITLE" --msgbox "Ключ не найден. Убедитесь, что сервер установлен и запущен." 10 60
  fi
}

web_info() {
  WAN_IP=$(curl -s -4 https://api64.ipify.org || echo "ВАШ_IP")
  whiptail --title "$TITLE" --msgbox "Веб-панель (только для Pro):\n\nURL: http://$WAN_IP:21114\nЛогин: admin\nПароль: test1234" 12 60
}

identify_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_LIKE=$ID_LIKE
  else
    OS_ID=$(uname -s)
  fi
}

install_deps() {
  echo -e "${CYAN}Установка зависимостей...${NC}"
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_LIKE" == *"debian"* ]]; then
    apt-get update
    apt-get install -y curl wget unzip tar dnsutils whiptail
  elif [[ "$OS_ID" == "centos" || "$OS_ID" == "rhel" || "$OS_ID" == "fedora" || "$OS_LIKE" == *"rhel"* || "$OS_LIKE" == *"fedora"* ]]; then
    yum install -y curl wget unzip tar bind-utils whiptail
  elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
    pacman -Syu --noconfirm
    pacman -S --noconfirm curl wget unzip tar bind whiptail
  else
    echo -e "${RED}Неподдерживаемая ОС. Попытка продолжить...${NC}"
    sleep 2
  fi
}

# Запуск
identify_os
install_deps

regenerate_keys() {
  if (whiptail --title "$TITLE" --yesno "Вы уверены, что хотите перегенерировать ключи безопасности? Это перезапустит службы." 10 60); then
    echo -e "${CYAN}Остановка служб...${NC}"
    systemctl stop rustdesk-hbbs.service 2>/dev/null
    systemctl stop rustdesk-hbbr.service 2>/dev/null
    systemctl stop rustdesksignal.service 2>/dev/null
    systemctl stop rustdeskrelay.service 2>/dev/null

    echo -e "${CYAN}Удаление старых ключей...${NC}"
    # Очистка в обоих возможных местах
    for dir in "$RUSTDESK_PRO_DIR" "$RUSTDESK_FREE_DIR"; do
      if [ -d "$dir" ]; then
        find "$dir" -maxdepth 1 -name "*.pub" | while read pubfile; do
          privfile="${pubfile%.pub}"
          [ -f "$pubfile" ] && rm -f "$pubfile"
          [ -f "$privfile" ] && rm -f "$privfile"
        done
      fi
    done

    echo -e "${CYAN}Запуск служб (новые ключи будут созданы автоматически)...${NC}"
    systemctl start rustdesk-hbbs.service 2>/dev/null
    systemctl start rustdesk-hbbr.service 2>/dev/null
    systemctl start rustdesksignal.service 2>/dev/null
    systemctl start rustdeskrelay.service 2>/dev/null

    whiptail --title "$TITLE" --msgbox "Ключи перегенерированы, службы перезапущены." 10 60
  fi
}

main_menu
