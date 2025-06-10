#!/bin/bash

# REALITY Server Auto-Installer v2.0
# Полная очистка + установка с нуля

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция логирования
log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +%H:%M:%S)] ❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠️  $1${NC}"
}

# Проверка root
if [[ $EUID -ne 0 ]]; then
   error "Этот скрипт должен быть запущен с правами root"
   exit 1
fi

clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════╗"
echo "║     REALITY VPN SERVER INSTALLER      ║"
echo "║           Version 2.0                 ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# ЭТАП 1: ПОЛНАЯ ОЧИСТКА
echo -e "\n${YELLOW}🧹 ЭТАП 1: ПОЛНАЯ ОЧИСТКА СИСТЕМЫ${NC}"
echo "=================================="

log "Остановка всех сервисов..."
systemctl stop xray v2ray v2ray-client 2>/dev/null || true
systemctl disable xray v2ray v2ray-client 2>/dev/null || true

log "Удаление systemd сервисов..."
rm -f /etc/systemd/system/xray.service
rm -f /etc/systemd/system/v2ray*.service
systemctl daemon-reload

log "Удаление исполняемых файлов..."
rm -f /usr/local/bin/xray
rm -f /usr/local/bin/v2ray
rm -f /usr/bin/xray
rm -f /usr/bin/v2ray

log "Удаление конфигураций..."
rm -rf /etc/xray/
rm -rf /etc/v2ray/
rm -rf /usr/local/etc/xray/
rm -rf /usr/local/etc/v2ray/

log "Удаление временных файлов..."
rm -f /tmp/xray*
rm -f /tmp/v2ray*
rm -f /tmp/reality*
rm -f /root/reality*
rm -f /root/client_setup.sh

log "Завершение процессов..."
pkill -f xray 2>/dev/null || true
pkill -f v2ray 2>/dev/null || true

log "✅ Очистка завершена!"

# ЭТАП 2: УСТАНОВКА
echo -e "\n${YELLOW}🚀 ЭТАП 2: УСТАНОВКА REALITY${NC}"
echo "================================"

log "Обновление системы..."
apt update > /dev/null 2>&1
apt install -y wget unzip curl net-tools qrencode > /dev/null 2>&1

log "Определение IP адреса..."
SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 ipinfo.io/ip)
if [ -z "$SERVER_IP" ]; then
    error "Не удалось определить IP адрес"
    exit 1
fi
log "IP сервера: $SERVER_IP"

log "Загрузка Xray..."
cd /tmp
wget -q https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
if [ ! -f "Xray-linux-64.zip" ]; then
    error "Не удалось скачать Xray"
    exit 1
fi

unzip -q Xray-linux-64.zip
chmod +x xray
mv xray /usr/local/bin/
mkdir -p /etc/xray

log "Генерация ключей..."
UUID=$(/usr/local/bin/xray uuid)
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# Сохранение конфигурации
cat > /root/reality_config.txt << EOF
REALITY VPN CONFIGURATION
========================
Server IP: $SERVER_IP
UUID: $UUID
Private Key: $PRIVATE_KEY
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
Port: 443
SNI: www.microsoft.com
EOF

log "Создание конфигурации Xray..."
cat > /etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "info"
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
            "www.microsoft.com"
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
    }
  ]
}
EOF

log "Проверка конфигурации..."
if ! /usr/local/bin/xray test -config /etc/xray/config.json > /dev/null 2>&1; then
    error "Ошибка в конфигурации Xray"
    cat /etc/xray/config.json
    exit 1
fi

log "Создание systemd сервиса..."
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

log "Настройка фаервола..."
if command -v ufw &> /dev/null; then
    ufw allow 443/tcp > /dev/null 2>&1
    ufw allow ssh > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1
fi

log "Запуск Xray..."
systemctl daemon-reload
systemctl enable xray > /dev/null 2>&1
systemctl start xray

sleep 3

if systemctl is-active --quiet xray; then
    log "✅ Xray запущен успешно!"
else
    error "Ошибка запуска Xray"
    systemctl status xray --no-pager
    exit 1
fi

# ЭТАП 3: СОЗДАНИЕ КЛИЕНТСКИХ КОНФИГУРАЦИЙ
echo -e "\n${YELLOW}📱 ЭТАП 3: СОЗДАНИЕ КОНФИГУРАЦИЙ${NC}"
echo "===================================="

# QR код для мобильных
VLESS_URL="vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-VPN"

# Скрипт для клиента n8n
cat > /root/client_setup.sh << 'EOF'
#!/bin/bash

# REALITY Client Installer for n8n

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ❌ $1${NC}"; }

if [[ $EUID -ne 0 ]]; then
   error "Запустите с правами root: sudo bash client_setup.sh"
   exit 1
fi

clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════╗"
echo "║    REALITY CLIENT FOR N8N INSTALLER   ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# Ввод данных
echo -e "${YELLOW}Введите данные с сервера:${NC}"
read -p "Server IP: " SERVER_IP
read -p "UUID: " UUID
read -p "Public Key: " PUBLIC_KEY
read -p "Short ID: " SHORT_ID

# Очистка старых установок
log "Очистка старых установок..."
systemctl stop v2ray-client 2>/dev/null || true
systemctl disable v2ray-client 2>/dev/null || true
rm -f /etc/systemd/system/v2ray-client.service
rm -rf /etc/v2ray/
rm -f /usr/local/bin/v2ray
pkill -f v2ray 2>/dev/null || true

# Установка v2ray
log "Установка v2ray..."
cd /tmp
wget -q https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip
unzip -q v2ray-linux-64.zip
chmod +x v2ray
mv v2ray /usr/local/bin/
mkdir -p /etc/v2ray

# Конфигурация
log "Создание конфигурации..."
cat > /etc/v2ray/config.json << EEOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks",
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": false
      }
    },
    {
      "tag": "http",
      "port": 10809,
      "listen": "127.0.0.1",
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_IP",
            "port": 443,
            "users": [
              {
                "id": "$UUID",
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName": "www.microsoft.com",
          "publicKey": "$PUBLIC_KEY",
          "shortId": "$SHORT_ID"
        }
      }
    }
  ]
}
EEOF

# Systemd сервис
cat > /etc/systemd/system/v2ray-client.service << EEOF
[Unit]
Description=V2Ray Client Service
After=network.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EEOF

# Запуск
log "Запуск v2ray клиента..."
systemctl daemon-reload
systemctl enable v2ray-client
systemctl start v2ray-client

sleep 3

if systemctl is-active --quiet v2ray-client; then
    log "✅ V2Ray клиент запущен!"
    
    # Тест
    log "Тестирование подключения..."
    if curl --socks5 127.0.0.1:10808 -s https://httpbin.org/ip | grep -q origin; then
        log "✅ Прокси работает!"
    fi
    
    # Перезапуск n8n
    log "Перезапуск n8n с прокси..."
    docker stop n8n 2>/dev/null || true
    docker run -d --name n8n \
      -p 5678:5678 \
      -v n8n_data:/home/node/.n8n \
      -e HTTP_PROXY=http://127.0.0.1:10809 \
      -e HTTPS_PROXY=http://127.0.0.1:10809 \
      docker.n8n.io/n8nio/n8n
      
    echo -e "\n${GREEN}🎉 ГОТОВО!${NC}"
    echo "SOCKS5: 127.0.0.1:10808"
    echo "HTTP: 127.0.0.1:10809"
    echo "n8n работает через Reality VPN!"
else
    error "Ошибка запуска клиента"
    systemctl status v2ray-client
fi
EOF

chmod +x /root/client_setup.sh

# ВЫВОД РЕЗУЛЬТАТОВ
clear
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════╗"
echo "║    🎉 REALITY СЕРВЕР НАСТРОЕН!        ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

echo -e "\n${YELLOW}📋 ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
echo "=============================="
echo "IP: $SERVER_IP"
echo "Port: 443"
echo "UUID: $UUID"
echo "Public Key: $PUBLIC_KEY"
echo "Short ID: $SHORT_ID"
echo "SNI: www.microsoft.com"

echo -e "\n${YELLOW}📱 QR-КОД ДЛЯ МОБИЛЬНЫХ:${NC}"
echo "$VLESS_URL" | qrencode -t ansiutf8

echo -e "\n${YELLOW}🔗 ССЫЛКА ДЛЯ ИМПОРТА:${NC}"
echo "$VLESS_URL"

echo -e "\n${YELLOW}💾 ФАЙЛЫ:${NC}"
echo "Конфигурация сохранена в: /root/reality_config.txt"
echo "Скрипт для клиента: /root/client_setup.sh"

echo -e "\n${YELLOW}📱 МОБИЛЬНЫЕ ПРИЛОЖЕНИЯ:${NC}"
echo "Android: v2rayNG (Google Play)"
echo "iOS: FairVPN или Shadowrocket"

echo -e "\n${GREEN}✅ Сервер готов к работе!${NC}"
