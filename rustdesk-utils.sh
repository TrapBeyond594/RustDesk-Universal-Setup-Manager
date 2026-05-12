#!/bin/bash

# Утилиты для RustDesk Server (Free & Pro)
TITLE="Утилиты RustDesk"
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

utils_menu() {
  while true; do
    CHOICE=$(whiptail --title "$TITLE" --menu "Выберите действие:" 20 75 10 \
      "1" "Статус всех служб" \
      "2" "Просмотр логов" \
      "3" "Управление ключами (просмотр/генерация)" \
      "4" "Информация о панели Pro (Админ, Пароль, IP)" \
      "5" "Изменить IP/Домен/DDNS" \
      "6" "Назад" 3>&1 1>&2 2>&3)

    case $CHOICE in
      1) show_status_dashboard ;;
      2) view_logs_menu ;;
      3) key_management_menu ;;
      4) pro_panel_info ;;
      5) change_address ;;
      6) exit 0 ;;
      *) exit 0 ;;
    esac
  done
}

show_status_dashboard() {
  SERVICES=("rustdesksignal" "rustdeskrelay" "rustdesk-hbbs" "rustdesk-hbbr" "gohttpserver" "nginx")
  STATUS_TEXT="Статус системных служб:\n\n"

  for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
      STATUS_TEXT+="${svc}: [АКТИВНА]\n"
    else
      if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        STATUS_TEXT+="${svc}: [ОШИБКА/ВЫКЛ]\n"
      else
        STATUS_TEXT+="${svc}: [НЕ УСТАНОВЛЕНА]\n"
      fi
    fi
  done

  whiptail --title "$TITLE - Дашборд" --msgbox "$STATUS_TEXT" 18 60
}

view_logs_menu() {
  LOG_CHOICE=$(whiptail --title "$TITLE - Логи" --menu "Выберите сервис:" 15 60 5 \
    "1" "Signal (Free) - hbbs" \
    "2" "Relay (Free) - hbbr" \
    "3" "HBBS (Pro)" \
    "4" "HBBR (Pro)" \
    "5" "GoHTTP (Free Extra)" 3>&1 1>&2 2>&3)

  case $LOG_CHOICE in
    1) tail -n 50 /var/log/rustdesk/signalserver.log | whiptail --title "Логи Signal Free" --textbox /dev/stdin 20 80 ;;
    2) tail -n 50 /var/log/rustdesk/relayserver.log | whiptail --title "Логи Relay Free" --textbox /dev/stdin 20 80 ;;
    3) tail -n 50 /var/log/rustdesk-server/hbbs.log | whiptail --title "Логи HBBS Pro" --textbox /dev/stdin 20 80 ;;
    4) tail -n 50 /var/log/rustdesk-server/hbbr.log | whiptail --title "Логи HBBR Pro" --textbox /dev/stdin 20 80 ;;
    5) tail -n 50 /var/log/gohttp/gohttpserver.log | whiptail --title "Логи GoHTTP" --textbox /dev/stdin 20 80 ;;
  esac
}

key_management_menu() {
  while true; do
    KEYS_INFO="Найденные ключи:\n\n"
    i=1
    declare -A KEY_FILES

    # Поиск ключей в обеих директориях
    while IFS= read -r pub; do
      date_val=$(stat -c %y "$pub" | cut -d. -f1)
      content=$(cat "$pub")

      # Проверка активного ключа
      ACTIVE_LABEL=""
      DIR_PATH=$(dirname "$pub")
      if [ -f "$DIR_PATH/id_ed25519.pub" ]; then
         ACTIVE_CONTENT=$(cat "$DIR_PATH/id_ed25519.pub")
         if [ "$content" == "$ACTIVE_CONTENT" ]; then
            ACTIVE_LABEL=" [АКТИВЕН]"
         fi
      fi

      KEYS_INFO+="$i) $pub$ACTIVE_LABEL\n   Создан: $date_val\n   Ключ: ${content:0:20}...\n\n"
      KEY_FILES[$i]=$pub
      i=$((i+1))
    done < <(find "$RUSTDESK_PRO_DIR" "$RUSTDESK_FREE_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null)

    [ $i -eq 1 ] && KEYS_INFO="Ключи не найдены."

    K_ACTION=$(whiptail --title "Управление ключами" --menu "$KEYS_INFO" 22 75 3 \
      "1" "Показать выбранный ключ полностью" \
      "2" "Перегенерировать (ротация) все ключи" \
      "3" "Назад" 3>&1 1>&2 2>&3)

    case $K_ACTION in
      1)
        K_NUM=$(whiptail --title "Выбор ключа" --inputbox "Введите номер ключа:" 10 60 3>&1 1>&2 2>&3)
        FILE=${KEY_FILES[$K_NUM]}
        if [ -f "$FILE" ]; then
          whiptail --title "Ключ: $FILE" --msgbox "$(cat "$FILE")" 12 70
        fi
        ;;
      2) regenerate_keys_logic ;;
      3) break ;;
      *) break ;;
    esac
  done
}

regenerate_keys_logic() {
  if whiptail --title "$TITLE" --yesno "Это удалит старые ключи и создаст новые. Службы будут перезапущены. Продолжить?" 10 60; then
    systemctl stop rustdesk-hbbs rustdesk-hbbr rustdesksignal rustdeskrelay 2>/dev/null
    find "$RUSTDESK_PRO_DIR" "$RUSTDESK_FREE_DIR" -maxdepth 1 -name "*.pub" -delete 2>/dev/null
    find "$RUSTDESK_PRO_DIR" "$RUSTDESK_FREE_DIR" -maxdepth 1 -name "id_ed25519" -delete 2>/dev/null
    systemctl start rustdesk-hbbs rustdesk-hbbr rustdesksignal rustdeskrelay 2>/dev/null
    whiptail --msgbox "Ключи перегенерированы." 8 40
  fi
}

pro_panel_info() {
  if [ ! -d "$RUSTDESK_PRO_DIR" ]; then
    whiptail --msgbox "Pro версия не установлена." 8 40
    return
  fi

  SAVED_ADDR="IP не определен"
  [ -f "$RUSTDESK_PRO_DIR/address.conf" ] && SAVED_ADDR=$(cat "$RUSTDESK_PRO_DIR/address.conf")

  DB_PATH="$RUSTDESK_PRO_DIR/db.sqlite3"

  ADMIN_USER="admin"
  ADMIN_PASS="test1234 (по умолчанию)"

  if [ -f "$DB_PATH" ]; then
     # Попытка найти кастомного админа и пароль (пароли в RustDesk Pro хешированы, но мы можем показать пользователей)
     USERS=$(sqlite3 "$DB_PATH" "SELECT username FROM users WHERE is_admin=1;" 2>/dev/null)
     [ -n "$USERS" ] && ADMIN_USER="$USERS"
     ADMIN_PASS="[ХЕШИРОВАН В БД]"
  fi

  whiptail --title "Информация о панели Pro" --msgbox "URL: http://$SAVED_ADDR:21114\nАдмин: $ADMIN_USER\nПароль: $ADMIN_PASS\n\nДля сброса пароля используйте 'rustdesk-utils set_password admin new_pass'" 15 60
}

change_address() {
  NEW_ADDR=$(whiptail --title "Смена адреса" --inputbox "Введите новый IP-адрес, DDNS или домен вашего сервера:" 10 60 3>&1 1>&2 2>&3)
  [ -z "$NEW_ADDR" ] && return

  # Сохраняем в обоих местах, если они существуют
  [ -d "$RUSTDESK_FREE_DIR" ] && echo "$NEW_ADDR" > "$RUSTDESK_FREE_DIR/address.conf"
  [ -d "$RUSTDESK_PRO_DIR" ] && echo "$NEW_ADDR" > "$RUSTDESK_PRO_DIR/address.conf"

  whiptail --msgbox "Адрес $NEW_ADDR успешно сохранен в конфигурации." 10 60
}

utils_menu
