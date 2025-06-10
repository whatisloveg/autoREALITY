#!/bin/bash

# REALITY Server Auto-Installer v3.0 FIXED
# С расширенной диагностикой и исправлением ошибок

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции логирования
log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +%H:%M:%S)] ❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠️  $1${NC}"
}

debug() {
    echo -e "${CYAN}[$(date +%H:%M:%S)] 🔍 DEBUG: $1${NC}"
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
echo "║         Version 3.0 FIXED             ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# ЭТАП 1: ПОЛНАЯ ОЧИСТКА
echo -e "\n${YELLOW}🧹 ЭТАП 1: ПОЛНАЯ ОЧИСТКА СИСТЕМЫ${NC}"
echo "=================================="

log "Остановка всех сервисов..."
for service in xray v2ray v2ray-client; do
    if systemctl is-active --quiet $service 2>/dev/null; then
        debug "Остановка $service..."
        systemctl stop $service 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet $service 2>/dev/null; then
        debug "Отключение автозапуска $service..."
        systemctl disable $service 2>/dev/null || true
    fi
done

log "Удаление systemd сервисов..."
rm -f /etc/systemd/system/xray.service
rm -f /etc/systemd/system/v2ray*.service
systemctl daemon-reload

log "Удаление исполняемых файлов..."
for file in /usr/local/bin/xray /usr/local/bin/v2ray /usr/bin/xray /usr/bin/v2ray; do
    if [ -f "$file" ]; then
        debug "Удаление $file"
        rm -f "$file"
    fi
done

log "Удаление конфигураций..."
for dir in /etc/xray /etc/v2ray /usr/local/etc/xray /usr/local/etc/v2ray; do
    if [ -d "$dir" ]; then
        debug "Удаление директории $dir"
        rm -rf "$dir"
    fi
done

log "Удаление временных файлов..."
rm -f /tmp/xray* /tmp/v2ray* /tmp/reality* /root/reality* /root/client_setup.sh

log "Завершение процессов..."
pkill -f xray 2>/dev/null || true
pkill -f v2ray 2>/dev/null || true

log "✅ Очистка завершена!"

# ЭТАП 2: УСТАНОВКА ЗАВИСИМОСТЕЙ
echo -e "\n${YELLOW}📦 ЭТАП 2: УСТАНОВКА ЗАВИСИМОСТЕЙ${NC}"
echo "====================================="

log "Обновление системы..."
apt update > /dev/null 2>&1 || {
    error "Ошибка обновления пакетов"
    exit 1
}

log "Установка необходимых пакетов..."
PACKAGES="wget unzip curl net-tools qrencode openssl"
for pkg in $PACKAGES; do
    if ! command -v $pkg &> /dev/null; then
        debug "Установка $pkg..."
        apt install -y $pkg > /dev/null 2>&1 || warning "Не удалось установить $pkg"
    fi
done

# ЭТАП 3: ОПРЕДЕЛЕНИЕ ПАРАМЕТРОВ
echo -e "\n${YELLOW}🌐 ЭТАП 3: ОПРЕДЕЛЕНИЕ ПАРАМЕТРОВ${NC}"
echo "===================================="

log "Определение IP адреса..."
SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 ipinfo.io/ip || curl -s4 api.ipify.org)
if [ -z "$SERVER_IP" ]; then
    error "Не удалось определить IP адрес"
    exit 1
fi
log "✅ IP сервера: $SERVER_IP"

# ЭТАП 4: УСТАНОВКА XRAY
echo -e "\n${YELLOW}🚀 ЭТАП 4: УСТАНОВКА XRAY${NC}"
echo "=============================="

log "Загрузка Xray..."
cd /tmp
rm -f Xray-linux-64.zip

debug "Скачивание с GitHub..."
if ! wget -q --show-progress https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip; then
    error "Не удалось скачать Xray"
    exit 1
fi

if [ ! -f "Xray-linux-64.zip" ]; then
    error "Файл Xray-linux-64.zip не найден"
    exit 1
fi

debug "Размер файла: $(ls -lh Xray-linux-64.zip | awk '{print $5}')"

log "Распаковка Xray..."
unzip -o -q Xray-linux-64.zip || {
    error "Ошибка распаковки архива"
    exit 1
}

if [ ! -f "xray" ]; then
    error "Исполняемый файл xray не найден после распаковки"
    exit 1
fi

chmod +x xray
mv xray /usr/local/bin/
mkdir -p /etc/xray

debug "Проверка установки Xray..."
if ! /usr/local/bin/xray version > /dev/null 2>&1; then
    error "Xray установлен некорректно"
    exit 1
fi

XRAY_VERSION=$(/usr/local/bin/xray version | grep -oP 'Xray \K[0-9.]+' | head -1)
log "✅ Xray $XRAY_VERSION установлен"

# ЭТАП 5: ГЕНЕРАЦИЯ КЛЮЧЕЙ
echo -e "\n${YELLOW}🔑 ЭТАП 5: ГЕНЕРАЦИЯ КЛЮЧЕЙ${NC}"
echo "==============================="

log "Генерация UUID..."
UUID=$(/usr/local/bin/xray uuid)
debug "UUID: $UUID"

log "Генерация ключевой пары x25519..."
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    error "Не удалось сгенерировать ключи"
    debug "Вывод команды: $KEYS"
    exit 1
fi

debug "Private Key: ${PRIVATE_KEY:0:20}..."
debug "Public Key: ${PUBLIC_KEY:0:20}..."

log "Генерация Short ID..."
SHORT_ID=$(openssl rand -hex 4)
debug "Short ID: $SHORT_ID"

# Сохранение конфигурации
cat > /root/reality_config.txt << EOF
REALITY VPN CONFIGURATION
========================
Generated: $(date)
Server IP: $SERVER_IP
UUID: $UUID
Private Key: $PRIVATE_KEY
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
Port: 443
SNI: www.microsoft.com
EOF

log "✅ Ключи сгенерированы и сохранены"

# ЭТАП 6: СОЗДАНИЕ КОНФИГУРАЦИИ
echo -e "\n${YELLOW}⚙️  ЭТАП 6: СОЗДАНИЕ КОНФИГУРАЦИИ${NC}"
echo "===================================="

log "Создание конфигурации Xray..."

# Базовая конфигурация для старых версий Xray
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
            "www.microsoft.com",
            "microsoft.com"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
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

log "Проверка конфигурации..."
debug "Запуск команды проверки..."

# Детальная проверка конфигурации
if ! /usr/local/bin/xray test -config /etc/xray/config.json 2>&1 | tee /tmp/xray_test.log; then
    error "Ошибка в конфигурации Xray"
    debug "Содержимое лога проверки:"
    cat /tmp/xray_test.log
    
    # Попытка исправить для новых версий
    warning "Пробуем альтернативную конфигурацию..."
    
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
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
    
    # Повторная проверка
    if ! /usr/local/bin/xray test -config /etc/xray/config.json; then
        error "Конфигурация все еще содержит ошибки"
        exit 1
    fi
fi

log "✅ Конфигурация корректна!"

# ЭТАП 7: НАСТРОЙКА SYSTEMD
echo -e "\n${YELLOW}🔧 ЭТАП 7: НАСТРОЙКА SYSTEMD${NC}"
echo "================================="

log "Создание systemd сервиса..."
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

log "Настройка фаервола..."
if command -v ufw &> /dev/null; then
    debug "Настройка UFW..."
    ufw allow 443/tcp > /dev/null 2>&1
    ufw allow ssh > /dev/null 2>&1
    ufw --force enable > /dev/null 2>&1
elif command -v firewall-cmd &> /dev/null; then
    debug "Настройка firewalld..."
    firewall-cmd --permanent --add-port=443/tcp > /dev/null 2>&1
    firewall-cmd --reload > /dev/null 2>&1
fi

# ЭТАП 8: ЗАПУСК СЕРВИСА
echo -e "\n${YELLOW}🚀 ЭТАП 8: ЗАПУСК СЕРВИСА${NC}"
echo "=============================="

log "Перезагрузка systemd..."
systemctl daemon-reload

log "Включение автозапуска..."
systemctl enable xray > /dev/null 2>&1

log "Запуск Xray..."
systemctl start xray

# Ожидание запуска
sleep 3

log "Проверка статуса..."
if systemctl is-active --quiet xray; then
    log "✅ Xray запущен успешно!"
    debug "PID процесса: $(systemctl show -p MainPID xray | cut -d= -f2)"
else
    error "Xray не запустился"
    warning "Вывод статуса:"
    systemctl status xray --no-pager
    warning "Последние логи:"
    journalctl -u xray -n 20 --no-pager
    exit 1
fi

# ЭТАП 9: СОЗДАНИЕ КЛИЕНТСКИХ КОНФИГУРАЦИЙ
echo -e "\n${YELLOW}📱 ЭТАП 9: СОЗДАНИЕ КОНФИГУРАЦИЙ${NC}"
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

# Создание скрипта диагностики
cat > /root/reality_check.sh << 'EOF'
#!/bin/bash

echo "=== REALITY SERVER DIAGNOSTICS ==="
echo ""

echo "1. Service Status:"
systemctl status xray --no-pager | head -10

echo ""
echo "2. Port Check:"
netstat -tlnp | grep :443

echo ""
echo "3. Recent Logs:"
journalctl -u xray -n 10 --no-pager

echo ""
echo "4. Config Test:"
/usr/local/bin/xray test -config /etc/xray/config.json

echo ""
echo "5. Connection Test:"
curl -s https://httpbin.org/ip
EOF

chmod +x /root/reality_check.sh

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
echo "Конфигурация: /root/reality_config.txt"
echo "Скрипт клиента: /root/client_setup.sh"
echo "Диагностика: /root/reality_check.sh"

echo -e "\n${YELLOW}📱 МОБИЛЬНЫЕ ПРИЛОЖЕНИЯ:${NC}"
echo "Android: v2rayNG (Google Play)"
echo "iOS: FairVPN или Shadowrocket"

echo -e "\n${YELLOW}🔧 КОМАНДЫ УПРАВЛЕНИЯ:${NC}"
echo "Статус: systemctl status xray"
echo "Логи: journalctl -u xray -f"
echo "Диагностика: bash /root/reality_check.sh"

echo -e "\n${GREEN}✅ Установка завершена успешно!${NC}"
