#!/bin/bash

# REALITY Server Universal Installer v5.0
# Автоматически адаптируется под любую версию Xray

set -euo pipefail
trap 'echo -e "\n❌ Установка прервана. Проверьте логи: journalctl -u xray -n 50"' ERR

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Логирование
log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ❌ $1${NC}"; }
warning() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠️  $1${NC}"; }
debug() { echo -e "${CYAN}[$(date +%H:%M:%S)] 🔍 $1${NC}"; }

# Проверка root
if [[ $EUID -ne 0 ]]; then
   error "Запустите с правами root: sudo bash $0"
   exit 1
fi

# Защита от разрыва SSH
export DEBIAN_FRONTEND=noninteractive
if [ -f /etc/ssh/sshd_config ]; then
    grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
    grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 120" >> /etc/ssh/sshd_config
    systemctl reload sshd 2>/dev/null || true
fi

clear
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════╗"
echo "║   REALITY VPN UNIVERSAL INSTALLER     ║"
echo "║           Version 5.0                 ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# Функция очистки
cleanup_system() {
    log "Очистка системы от старых установок..."
    
    # Остановка сервисов
    for service in xray v2ray v2ray-client; do
        systemctl stop $service 2>/dev/null || true
        systemctl disable $service 2>/dev/null || true
    done
    
    # Удаление файлов
    rm -f /etc/systemd/system/{xray,v2ray}*.service
    rm -rf /etc/{xray,v2ray} /usr/local/etc/{xray,v2ray}
    rm -f /usr/local/bin/{xray,v2ray} /usr/bin/{xray,v2ray}
    rm -f /tmp/{xray,v2ray,reality}* /root/{reality,client_setup,xray,v2ray}*.{sh,txt,log}
    
    # Завершение процессов
    pkill -f xray 2>/dev/null || true
    pkill -f v2ray 2>/dev/null || true
    
    systemctl daemon-reload
    log "✅ Очистка завершена"
}

# Функция установки зависимостей
install_dependencies() {
    log "Установка зависимостей..."
    
    # Обновление репозиториев
    apt-get update -qq || {
        error "Не удалось обновить репозитории"
        exit 1
    }
    
    # Установка пакетов
    local packages=(wget unzip curl net-tools qrencode openssl jq)
    for pkg in "${packages[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            debug "Установка $pkg..."
            apt-get install -y $pkg > /dev/null 2>&1 || warning "Не удалось установить $pkg"
        fi
    done
    
    log "✅ Зависимости установлены"
}

# Функция определения IP
get_server_ip() {
    log "Определение IP адреса сервера..."
    
    local ip=""
    for service in ifconfig.me ipinfo.io/ip api.ipify.org icanhazip.com; do
        ip=$(curl -s4 --max-time 5 $service 2>/dev/null)
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        fi
    done
    
    if [ -z "$ip" ]; then
        error "Не удалось определить внешний IP"
        exit 1
    fi
    
    SERVER_IP=$ip
    log "✅ IP сервера: $SERVER_IP"
}

# Функция установки Xray
install_xray() {
    log "Установка Xray..."
    
    # Получение последней версии
    local latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    if [ -z "$latest_version" ]; then
        warning "Не удалось получить последнюю версию, используем стабильную"
        latest_version="v1.8.16"
    fi
    log "Версия для установки: $latest_version"
    
    # Загрузка
    cd /tmp
    rm -f Xray-linux-64.zip
    local download_url="https://github.com/XTLS/Xray-core/releases/download/${latest_version}/Xray-linux-64.zip"
    
    debug "Загрузка с $download_url"
    if ! wget -q --show-progress "$download_url" -O Xray-linux-64.zip; then
        error "Не удалось загрузить Xray"
        exit 1
    fi
    
    # Установка
    unzip -o -q Xray-linux-64.zip || {
        error "Ошибка распаковки архива"
        exit 1
    }
    
    chmod +x xray
    mv xray /usr/local/bin/
    mkdir -p /etc/xray
    
    # Проверка
    if ! /usr/local/bin/xray version &> /dev/null; then
        error "Xray установлен некорректно"
        exit 1
    fi
    
    XRAY_VERSION=$(/usr/local/bin/xray version | head -1 | awk '{print $2}')
    log "✅ Xray $XRAY_VERSION установлен"
}

# Функция генерации ключей
generate_keys() {
    log "Генерация ключей..."
    
    UUID=$(/usr/local/bin/xray uuid)
    KEYS=$(/usr/local/bin/xray x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    SHORT_ID=$(openssl rand -hex 4)
    
    if [ -z "$UUID" ] || [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        error "Ошибка генерации ключей"
        exit 1
    fi
    
    log "✅ Ключи сгенерированы"
}

# Функция создания конфигурации
create_config() {
    log "Создание конфигурации..."
    
    # Минимальная тестовая конфигурация
    local test_config=$(cat <<EOF
{
  "inbounds": [{
    "port": 9999,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "1.1.1.1:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "$PRIVATE_KEY",
        "shortIds": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
)
    
    # Проверка какой формат поддерживается
    echo "$test_config" > /tmp/test_reality.json
    
    local config_works=false
    if /usr/local/bin/xray test -config /tmp/test_reality.json &> /dev/null; then
        config_works=true
        debug "Базовая конфигурация поддерживается"
    fi
    rm -f /tmp/test_reality.json
    
    # Создание рабочей конфигурации
    if [ "$config_works" = true ]; then
        # Современная минимальная конфигурация
        cat > /etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
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
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "statsUserUplink": false,
        "statsUserDownlink": false,
        "bufferSize": 512
      }
    },
    "system": {
      "statsInboundDownlink": false,
      "statsInboundUplink": false,
      "statsOutboundDownlink": false,
      "statsOutboundUplink": false
    }
  }
}
EOF
    else
        # Старый формат конфигурации
        warning "Используем альтернативный формат конфигурации"
        cat > /etc/xray/config.json << EOF
{
  "log": {
    "loglevel": "warning"
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
            "",
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
    fi
    
    # Создание директории для логов
    mkdir -p /var/log/xray
    chown nobody:nogroup /var/log/xray
    
    # Финальная проверка
    if ! /usr/local/bin/xray test -config /etc/xray/config.json &> /tmp/xray_config_test.log; then
        error "Ошибка в конфигурации:"
        cat /tmp/xray_config_test.log
        
        # Попытка автоматического исправления
        warning "Пытаюсь исправить конфигурацию..."
        
        # Убираем проблемные параметры
        jq 'del(.inbounds[0].streamSettings.realitySettings.minClientVer) | 
            del(.inbounds[0].streamSettings.realitySettings.maxClientVer) |
            del(.inbounds[0].streamSettings.realitySettings.maxTimeDiff) |
            .inbounds[0].streamSettings.realitySettings.shortIds = [$SHORT_ID]' \
            /etc/xray/config.json > /tmp/fixed_config.json 2>/dev/null || true
        
        if [ -f /tmp/fixed_config.json ] && /usr/local/bin/xray test -config /tmp/fixed_config.json &> /dev/null; then
            mv /tmp/fixed_config.json /etc/xray/config.json
            log "✅ Конфигурация исправлена"
        else
            error "Не удалось исправить конфигурацию автоматически"
            exit 1
        fi
    fi
    
    log "✅ Конфигурация создана и проверена"
}

# Функция настройки systemd
setup_systemd() {
    log "Настройка systemd сервиса..."
    
    cat > /etc/systemd/system/xray.service << 'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=always
RestartSec=3
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    
    # Права доступа
    chmod 644 /etc/systemd/system/xray.service
    chmod 644 /etc/xray/config.json
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    log "✅ Systemd сервис настроен"
}

# Функция настройки фаервола
setup_firewall() {
    log "Настройка фаервола..."
    
    # UFW
    if command -v ufw &> /dev/null; then
        ufw allow 443/tcp > /dev/null 2>&1
        ufw allow 22/tcp > /dev/null 2>&1
        yes | ufw enable > /dev/null 2>&1
        debug "UFW настроен"
    fi
    
    # firewalld
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=443/tcp > /dev/null 2>&1
        firewall-cmd --permanent --add-port=22/tcp > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        debug "firewalld настроен"
    fi
    
    # iptables
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
        debug "iptables настроен"
    fi
    
    log "✅ Фаервол настроен"
}

# Функция запуска сервиса
start_service() {
    log "Запуск Xray сервиса..."
    
    systemctl enable xray > /dev/null 2>&1
    systemctl start xray
    
    # Ожидание запуска
    local attempts=0
    while [ $attempts -lt 10 ]; do
        if systemctl is-active --quiet xray; then
            log "✅ Xray успешно запущен!"
            return 0
        fi
        sleep 1
        ((attempts++))
    done
    
    error "Xray не запустился. Диагностика:"
    systemctl status xray --no-pager
    journalctl -u xray -n 50 --no-pager
    return 1
}

# Функция создания клиентских скриптов
create_client_scripts() {
    log "Создание клиентских конфигураций..."
    
    # Сохранение основной конфигурации
    cat > /root/reality_config.txt << EOF
========================================
     REALITY VPN SERVER CONFIGURATION
========================================
Generated: $(date)
Server Version: $XRAY_VERSION

CONNECTION DETAILS:
------------------
Server IP: $SERVER_IP
Port: 443
Protocol: VLESS with Reality

CREDENTIALS:
------------
UUID: $UUID
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
SNI: www.microsoft.com
Fingerprint: chrome
Flow: xtls-rprx-vision

IMPORT LINK:
------------
vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-VPN

MOBILE APPS:
------------
Android: v2rayNG
iOS: FairVPN or Shadowrocket
========================================
EOF
    
    # Генерация QR кода
    local vless_url="vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Reality-VPN"
    
    # Скрипт установки клиента
    cat > /root/client_setup.sh << 'CLIENTEOF'
#!/bin/bash

# Reality Client Auto-Installer

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ❌ $1${NC}"; }
warning() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠️  $1${NC}"; }

if [[ $EUID -ne 0 ]]; then
   error "Запустите с правами root"
   exit 1
fi

clear
echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    REALITY CLIENT AUTO-INSTALLER      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
echo

# Чтение конфигурации если есть
if [ -f "/root/reality_config.txt" ]; then
    log "Найдена конфигурация сервера"
    SERVER_IP=$(grep "Server IP:" /root/reality_config.txt | awk '{print $3}')
    UUID=$(grep "UUID:" /root/reality_config.txt | awk '{print $2}')
    PUBLIC_KEY=$(grep "Public Key:" /root/reality_config.txt | awk '{print $3}')
    SHORT_ID=$(grep "Short ID:" /root/reality_config.txt | awk '{print $3}')
    
    if [ -n "$SERVER_IP" ] && [ -n "$UUID" ] && [ -n "$PUBLIC_KEY" ] && [ -n "$SHORT_ID" ]; then
        echo -e "${GREEN}Автоматически загружены данные:${NC}"
        echo "Server: $SERVER_IP"
        echo "UUID: ${UUID:0:8}..."
        echo
        read -p "Использовать эти данные? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            unset SERVER_IP UUID PUBLIC_KEY SHORT_ID
        fi
    fi
fi

# Ручной ввод если нужно
if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}Введите данные подключения:${NC}"
    read -p "Server IP: " SERVER_IP
    read -p "UUID: " UUID
    read -p "Public Key: " PUBLIC_KEY
    read -p "Short ID: " SHORT_ID
fi

# Очистка
log "Очистка старых установок..."
systemctl stop v2ray-client 2>/dev/null || true
systemctl disable v2ray-client 2>/dev/null || true
rm -rf /etc/v2ray /usr/local/bin/v2ray
pkill -f v2ray 2>/dev/null || true

# Установка V2Ray
log "Загрузка V2Ray..."
cd /tmp
rm -f v2ray-linux-64.zip
wget -q --show-progress https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip
unzip -o -q v2ray-linux-64.zip
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
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": false
      }
    },
    {
      "port": 10809,
      "listen": "127.0.0.1",
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
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

# Systemd
cat > /etc/systemd/system/v2ray-client.service << 'EEOF'
[Unit]
Description=V2Ray Client
After=network.target

[Service]
Type=simple
User=nobody
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EEOF

# Запуск
log "Запуск V2Ray клиента..."
systemctl daemon-reload
systemctl enable v2ray-client
systemctl start v2ray-client

sleep 2

if systemctl is-active --quiet v2ray-client; then
    log "✅ Клиент запущен!"
    
    # Тест
    log "Проверка соединения..."
    if timeout 10 curl -x socks5://127.0.0.1:10808 -s https://httpbin.org/ip | grep -q origin; then
        NEW_IP=$(curl -x socks5://127.0.0.1:10808 -s https://httpbin.org/ip | jq -r .origin)
        log "✅ VPN работает! Новый IP: $NEW_IP"
    fi
    
    # n8n
    if command -v docker &> /dev/null && docker ps -a | grep -q n8n; then
        log "Перенастройка n8n..."
        docker stop n8n 2>/dev/null || true
        docker rm n8n 2>/dev/null || true
        docker run -d --restart unless-stopped --name n8n \
          -p 5678:5678 \
          -v n8n_data:/home/node/.n8n \
          -e HTTP_PROXY=http://127.0.0.1:10809 \
          -e HTTPS_PROXY=http://127.0.0.1:10809 \
          docker.n8n.io/n8nio/n8n
        log "✅ n8n перезапущен с VPN"
    fi
    
    echo
    echo -e "${GREEN}═══════════════════════════════════${NC}"
    echo -e "${GREEN}✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!${NC}"
    echo -e "${GREEN}═══════════════════════════════════${NC}"
    echo
    echo "SOCKS5 прокси: 127.0.0.1:10808"
    echo "HTTP прокси: 127.0.0.1:10809"
    echo
    echo "Проверка: curl -x socks5://127.0.0.1:10808 https://httpbin.org/ip"
else
    error "Клиент не запустился"
    systemctl status v2ray-client --no-pager
fi
CLIENTEOF
    
    chmod +x /root/client_setup.sh
    
    # Скрипт диагностики
    cat > /root/reality_diagnostics.sh << 'DIAGEOF'
#!/bin/bash

YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}     REALITY SERVER DIAGNOSTICS${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo

# Статус сервиса
echo -e "${YELLOW}▶ Service Status:${NC}"
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}✓ Xray is running${NC}"
    echo "  PID: $(systemctl show -p MainPID xray | cut -d= -f2)"
    echo "  Uptime: $(systemctl show -p ActiveEnterTimestamp xray | cut -d= -f2-)"
else
    echo -e "${RED}✗ Xray is not running${NC}"
fi
echo

# Порты
echo -e "${YELLOW}▶ Port Status:${NC}"
if netstat -tlnp 2>/dev/null | grep -q ":443"; then
    echo -e "${GREEN}✓ Port 443 is listening${NC}"
else
    echo -e "${RED}✗ Port 443 is not listening${NC}"
fi
echo

# Последние логи
echo -e "${YELLOW}▶ Recent Logs:${NC}"
journalctl -u xray -n 10 --no-pager
echo

# Конфигурация
echo -e "${YELLOW}▶ Configuration Test:${NC}"
if /usr/local/bin/xray test -config /etc/xray/config.json &> /dev/null; then
    echo -e "${GREEN}✓ Configuration is valid${NC}"
else
    echo -e "${RED}✗ Configuration has errors${NC}"
fi
echo

# Использование ресурсов
echo -e "${YELLOW}▶ Resource Usage:${NC}"
systemctl status xray --no-pager | grep -E "Memory:|CPU:" || echo "No resource data available"
echo

# Сетевые соединения
echo -e "${YELLOW}▶ Active Connections:${NC}"
netstat -tnp 2>/dev/null | grep xray | wc -l | xargs echo "Total connections:"

echo -e "${YELLOW}════════════════════════════════════════${NC}"
DIAGEOF
    
    chmod +x /root/reality_diagnostics.sh
    
    # QR код
    echo -e "\n${YELLOW}📱 QR-КОД ДЛЯ МОБИЛЬНЫХ УСТРОЙСТВ:${NC}"
    echo "$vless_url" | qrencode -t ansiutf8 || {
        warning "QR код не сгенерирован (установите qrencode)"
        echo -e "\n${YELLOW}Ссылка для импорта:${NC}"
        echo "$vless_url"
    }
    
    log "✅ Клиентские конфигурации созданы"
}

# Функция вывода результатов
show_results() {
    clear
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════╗"
    echo "║    🎉 УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!    ║"
    echo "╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "\n${YELLOW}📋 ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "IP сервера: $SERVER_IP"
    echo "Порт: 443"
    echo "UUID: $UUID"
    echo "Public Key: $PUBLIC_KEY"
    echo "Short ID: $SHORT_ID"
    echo "SNI: www.microsoft.com"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo -e "\n${YELLOW}📂 СОЗДАННЫЕ ФАЙЛЫ:${NC}"
    echo "• Конфигурация: /root/reality_config.txt"
    echo "• Клиент для n8n: /root/client_setup.sh"
    echo "• Диагностика: /root/reality_diagnostics.sh"
    
    echo -e "\n${YELLOW}📱 ПОДКЛЮЧЕНИЕ С МОБИЛЬНЫХ:${NC}"
    echo "• Android: установите v2rayNG"
    echo "• iOS: установите FairVPN или Shadowrocket"
    echo "• Отсканируйте QR-код выше"
    
    echo -e "\n${YELLOW}💻 ПОДКЛЮЧЕНИЕ N8N:${NC}"
    echo "1. Скопируйте на сервер с n8n:"
    echo "   ${CYAN}scp root@$SERVER_IP:/root/client_setup.sh ./${NC}"
    echo "2. Запустите:"
    echo "   ${CYAN}sudo bash client_setup.sh${NC}"
    
    echo -e "\n${YELLOW}🔧 УПРАВЛЕНИЕ СЕРВЕРОМ:${NC}"
    echo "• Статус: ${CYAN}systemctl status xray${NC}"
    echo "• Логи: ${CYAN}journalctl -u xray -f${NC}"
    echo "• Диагностика: ${CYAN}bash /root/reality_diagnostics.sh${NC}"
    echo "• Перезапуск: ${CYAN}systemctl restart xray${NC}"
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Сервер готов к использованию!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ==================== ОСНОВНОЙ ПРОЦЕСС ====================

main() {
    # Отключаем выход при ошибке для основной функции
    set +e
    
    # Засекаем время
    START_TIME=$(date +%s)
    
    # Выполнение этапов
    cleanup_system || {
        error "Ошибка при очистке системы"
        exit 1
    }
    
    install_dependencies || {
        error "Ошибка установки зависимостей"
        exit 1
    }
    
    get_server_ip || {
        error "Ошибка определения IP"
        exit 1
    }
    
    install_xray || {
        error "Ошибка установки Xray"
        exit 1
    }
    
    generate_keys || {
        error "Ошибка генерации ключей"
        exit 1
    }
    
    create_config || {
        error "Ошибка создания конфигурации"
        exit 1
    }
    
    setup_systemd || {
        error "Ошибка настройки systemd"
        exit 1
    }
    
    setup_firewall || {
        error "Ошибка настройки фаервола"
        exit 1
    }
    
    start_service || {
        error "Ошибка запуска сервиса"
        exit 1
    }
    
    create_client_scripts || {
        error "Ошибка создания клиентских скриптов"
        exit 1
    }
    
    # Время выполнения
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Вывод результатов
    show_results
    
    log "Время установки: ${DURATION} секунд"
    
    # Убираем ловушку ошибок
    trap - ERR
}

# Запуск
main "$@"
