#!/bin/bash

# =============================================================================
# СКРИПТ 1: НАСТРОЙКА REALITY СЕРВЕРА
# Сохраните как: reality_server_setup.sh
# Запуск: sudo bash reality_server_setup.sh
# =============================================================================

echo "🚀 НАСТРОЙКА REALITY СЕРВЕРА"
echo "============================"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Запустите скрипт с правами root: sudo bash reality_server_setup.sh"
   exit 1
fi

echo "🔍 Проверка существующих установок..."

# =============================================================================
# ЭТАП 1: ПОЛНАЯ ОЧИСТКА СИСТЕМЫ
# =============================================================================

echo "🛑 Остановка всех связанных сервисов..."

# Остановка и отключение всех возможных сервисов
systemctl stop xray 2>/dev/null || true
systemctl stop xray.service 2>/dev/null || true
systemctl stop v2ray 2>/dev/null || true
systemctl stop v2ray.service 2>/dev/null || true
systemctl stop v2ray-client 2>/dev/null || true
systemctl stop v2ray-client.service 2>/dev/null || true

systemctl disable xray 2>/dev/null || true
systemctl disable xray.service 2>/dev/null || true
systemctl disable v2ray 2>/dev/null || true
systemctl disable v2ray.service 2>/dev/null || true
systemctl disable v2ray-client 2>/dev/null || true
systemctl disable v2ray-client.service 2>/dev/null || true

echo "🗑️ Удаление файлов сервисов..."

# Удаление systemd сервисов
rm -f /etc/systemd/system/xray.service
rm -f /etc/systemd/system/v2ray.service
rm -f /etc/systemd/system/v2ray-client.service
rm -f /lib/systemd/system/xray.service
rm -f /lib/systemd/system/v2ray.service
rm -f /lib/systemd/system/v2ray-client.service

# Перезагрузка systemd
systemctl daemon-reload
systemctl reset-failed

echo "🗂️ Удаление исполняемых файлов..."

# Удаление исполняемых файлов
rm -f /usr/local/bin/xray
rm -f /usr/local/bin/v2ray
rm -f /usr/bin/xray
rm -f /usr/bin/v2ray
rm -f /opt/xray
rm -f /opt/v2ray

echo "📁 Удаление конфигурационных директорий..."

# Удаление конфигурационных директорий
rm -rf /etc/xray/
rm -rf /etc/v2ray/
rm -rf /usr/local/etc/xray/
rm -rf /usr/local/etc/v2ray/
rm -rf /var/log/xray/
rm -rf /var/log/v2ray/

echo "🧽 Удаление временных файлов..."

# Удаление временных и рабочих файлов
rm -rf /tmp/xray*
rm -rf /tmp/v2ray*
rm -rf /tmp/Xray*
rm -rf /tmp/V2ray*
rm -f /tmp/reality_keys.txt
rm -f /root/reality_config.txt
rm -f /root/reality_check.sh

echo "🔄 Очистка процессов..."

# Убиваем все возможные процессы
pkill -f xray 2>/dev/null || true
pkill -f v2ray 2>/dev/null || true
pkill -f reality 2>/dev/null || true

# Ждем завершения процессов
sleep 2

echo "✅ Система полностью очищена от предыдущих установок"

# =============================================================================
# ЭТАП 2: СВЕЖАЯ УСТАНОВКА СЕРВЕРА
# =============================================================================

echo ""
echo "🚀 НАЧИНАЕМ СВЕЖУЮ УСТАНОВКУ REALITY СЕРВЕРА"
echo "==========================================="

# Обновление системы
echo "📦 Обновление системы..."
apt update && apt upgrade -y
apt install wget unzip curl net-tools -y

# Настройка времени
echo "⏰ Настройка времени..."
timedatectl set-timezone UTC

# Получение внешнего IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
echo "🌐 Внешний IP сервера: $SERVER_IP"

if [ -z "$SERVER_IP" ]; then
    echo "❌ Не удалось определить внешний IP сервера!"
    echo "Введите IP сервера вручную:"
    read -p "IP сервера: " SERVER_IP
fi

# Создание рабочих директорий
echo "📁 Создание директорий..."
mkdir -p /etc/xray
mkdir -p /var/log/xray

# Установка Xray
echo "⬇️ Скачивание и установка Xray..."
cd /tmp
rm -f Xray-linux-64.zip* xray*

# Попытка скачать с основного источника
if ! wget -q https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip; then
    echo "⚠️ Основной источник недоступен, пробуем альтернативный..."
    wget -q https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip
fi

if [ ! -f "Xray-linux-64.zip" ]; then
    echo "❌ Не удалось скачать Xray!"
    exit 1
fi

unzip -q Xray-linux-64.zip
chmod +x xray

# Проверка архитектуры
if ! ./xray version; then
    echo "❌ Неподходящая архитектура или поврежденный файл!"
    exit 1
fi

mv xray /usr/local/bin/
rm -f Xray-linux-64.zip LICENSE README.md

echo "✅ Xray установлен: $(/usr/local/bin/xray version | head -1)"

# Генерация ключей
echo "🔑 Генерация новых ключей..."
UUID=$(/usr/local/bin/xray uuid)
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# Проверка генерации ключей
if [ -z "$UUID" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
    echo "❌ Ошибка генерации ключей!"
    exit 1
fi

echo "✅ Ключи сгенерированы успешно"

# Сохранение ключей
cat > /root/reality_config.txt << EOF
SERVER_IP=$SERVER_IP
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
EOF

cat > /root/reality_info.txt << EOF
=== КОНФИГУРАЦИЯ REALITY СЕРВЕРА ===
Дата создания: $(date)
Внешний IP: $SERVER_IP
UUID: $UUID
Private Key: $PRIVATE_KEY
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID

=== ДЛЯ КЛИЕНТОВ ===
Адрес сервера: $SERVER_IP
Порт: 443
UUID: $UUID
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
SNI: www.microsoft.com
Fingerprint: chrome
Flow: xtls-rprx-vision
Security: reality
Network: tcp
EOF

echo "💾 Конфигурация сохранена в /root/reality_config.txt и /root/reality_info.txt"

# Создание конфигурации сервера
echo "⚙️ Создание конфигурации сервера..."
cat > /etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": [
            "www.microsoft.com",
            "microsoft.com"
          ],
          "privateKey": "$PRIVATE_KEY",
          "minClientVer": "1.8.0",
          "maxTimeDiff": 0,
          "shortIds": [
            "",
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

# Проверка конфигурации
echo "🔍 Проверка конфигурации..."
if ! /usr/local/bin/xray test -config /etc/xray/config.json; then
    echo "❌ Ошибка в конфигурации!"
    cat /etc/xray/config.json
    exit 1
fi

echo "✅ Конфигурация корректна"

# Создание systemd сервиса
echo "🔧 Создание systemd сервиса..."
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Настройка прав доступа
chown -R nobody:nogroup /var/log/xray
chmod 755 /var/log/xray

# Настройка фаервола
echo "🛡️ Настройка фаервола..."

# Проверка установки ufw
if ! command -v ufw &> /dev/null; then
    apt install ufw -y
fi

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 22/tcp
ufw allow 443/tcp
ufw --force enable

echo "✅ Фаервол настроен"

# Запуск сервиса
echo "🚀 Запуск Xray сервиса..."
systemctl daemon-reload
systemctl enable xray
systemctl start xray

# Проверка статуса с задержкой
sleep 5
if systemctl is-active --quiet xray; then
    echo "✅ Xray сервис запущен успешно!"
    
    # Проверка порта
    if netstat -tlnp | grep -q ":443.*xray"; then
        echo "✅ Сервис слушает на порту 443"
    else
        echo "⚠️ Предупреждение: порт 443 не прослушивается"
        netstat -tlnp | grep ":443"
    fi
else
    echo "❌ Ошибка запуска Xray сервиса!"
    echo "Логи сервиса:"
    systemctl status xray --no-pager -l
    echo ""
    echo "Последние логи:"
    journalctl -u xray --no-pager -n 20
    exit 1
fi

# Создание скрипта диагностики
echo "🔍 Создание скрипта диагностики..."
cat > /root/reality_check.sh << 'EOF'
#!/bin/bash

echo "🔍 ДИАГНОСТИКА REALITY СЕРВЕРА"
echo "============================="

echo "1. 🖥️ Статус сервера Xray:"
systemctl status xray --no-pager -l

echo ""
echo "2. 🔗 Порты (443 должен слушать Xray):"
netstat -tlnp | grep -E "(443|10808|10809)"

echo ""
echo "3. 📊 Последние подключения (5 минут):"
journalctl -u xray --since "5 minutes ago" --no-pager | tail -10

echo ""
echo "4. 🌐 Внешний IP сервера:"
curl -s ifconfig.me || curl -s ipinfo.io/ip

echo ""
echo "5. ⏰ Время сервера:"
date

echo ""
echo "6. 🔥 Фаервол (UFW) статус:"
ufw status numbered

echo ""
echo "7. 💾 Конфигурация клиента:"
if [ -f /root/reality_info.txt ]; then
    cat /root/reality_info.txt
else
    echo "❌ Файл конфигурации не найден!"
fi

echo ""
echo "8. 🔧 Процессы Xray:"
ps aux | grep -E "(xray|v2ray)" | grep -v grep

echo ""
echo "9. 📁 Файловая система:"
ls -la /etc/xray/
ls -la /usr/local/bin/xray
EOF

chmod +x /root/reality_check.sh

echo ""
echo "🎉 REALITY СЕРВЕР УСТАНОВЛЕН УСПЕШНО!"
echo "====================================="
echo ""
echo "📋 Файлы созданы:"
echo "   📄 /root/reality_config.txt - переменные конфигурации"
echo "   📄 /root/reality_info.txt - информация для клиентов"
echo "   🔍 /root/reality_check.sh - скрипт диагностики"
echo ""
echo "🔄 СЛЕДУЮЩИЕ ШАГИ:"
echo "   1. Для получения QR-кода: bash reality_qr_generator.sh"
echo "   2. Для настройки клиента: скопируйте reality_client_setup.sh на сервер с n8n"
echo ""
echo "🔧 Управление сервером:"
echo "   - Статус: systemctl status xray"
echo "   - Логи: journalctl -u xray -f"
echo "   - Диагностика: bash /root/reality_check.sh"
echo ""
echo "✅ Сервер готов к подключениям!"
echo ""
cat /root/reality_info.txt
