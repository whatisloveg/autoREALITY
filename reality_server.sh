#!/bin/bash

# =============================================================================
# REALITY VPN SERVER SETUP
# Версия: 1.0 Final
# =============================================================================

clear
echo "🚀 REALITY VPN SERVER SETUP"
echo "==========================="
echo ""

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Запустите с правами root: sudo bash $0"
   exit 1
fi

# Функция логирования
log() {
    echo "$(date '+%H:%M:%S') $1"
}

log "🔄 Начинаем установку..."

# =============================================================================
# ОЧИСТКА СИСТЕМЫ
# =============================================================================

log "🧹 Очистка предыдущих установок..."

# Остановка сервисов
systemctl stop xray 2>/dev/null || true
systemctl stop v2ray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
systemctl disable v2ray 2>/dev/null || true

# Удаление файлов
rm -rf /etc/xray/ /etc/v2ray/ 2>/dev/null || true
rm -f /usr/local/bin/xray /usr/local/bin/v2ray 2>/dev/null || true
rm -f /etc/systemd/system/xray.service /etc/systemd/system/v2ray.service 2>/dev/null || true

# Очистка процессов
pkill -f xray 2>/dev/null || true
pkill -f v2ray 2>/dev/null || true

systemctl daemon-reload

log "✅ Система очищена"

# =============================================================================
# УСТАНОВКА ЗАВИСИМОСТЕЙ
# =============================================================================

log "📦 Обновление системы..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wget unzip curl qrencode net-tools ufw

# Настройка времени
timedatectl set-timezone UTC

log "✅ Зависимости установлены"

# =============================================================================
# ОПРЕДЕЛЕНИЕ IP
# =============================================================================

log "🌐 Определение внешнего IP..."

SERVER_IP=""
for service in "ifconfig.me" "ipinfo.io/ip" "icanhazip.com"; do
    SERVER_IP=$(timeout 10 curl -s https://$service 2>/dev/null)
    if [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
done

if [[ ! $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log "❌ Не удалось определить IP автоматически"
    read -p "Введите IP сервера вручную: " SERVER_IP
fi

log "✅ IP сервера: $SERVER_IP"

# =============================================================================
# УСТАНОВКА XRAY
# =============================================================================

log "⬇️ Скачивание Xray..."

cd /tmp
rm -f Xray-*.zip xray 2>/dev/null

# Попытка скачать
if ! wget -q --timeout=30 https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip; then
    log "⚠️ Основной источник недоступен, пробуем альтернативный..."
    if ! wget -q --timeout=30 https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip; then
        log "❌ Не удалось скачать Xray"
        exit 1
    fi
fi

unzip -q Xray-linux-64.zip
chmod +x xray

# Проверка
if ! ./xray version >/dev/null 2>&1; then
    log "❌ Ошибка: неподходящая архитектура"
    exit 1
fi

# Создание директорий
mkdir -p /etc/xray /var/log/xray

# Установка
mv xray /usr/local/bin/
rm -f Xray-linux-64.zip *.md

log "✅ Xray установлен"

# =============================================================================
# ГЕНЕРАЦИЯ КЛЮЧЕЙ
# =============================================================================

log "🔑 Генерация ключей..."

UUID=$(/usr/local/bin/xray uuid)
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# Проверка генерации
if [[ -z "$UUID" || -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" || -z "$SHORT_ID" ]]; then
    log "❌ Ошибка генерации ключей"
    exit 1
fi

log "✅ Ключи сгенерированы"

# =============================================================================
# СОЗДАНИЕ КОНФИГУРАЦИИ
# =============================================================================

log "⚙️ Создание конфигурации..."

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

# Проверка конфигурации
if ! /usr/local/bin/xray test -config /etc/xray/config.json >/dev/null 2>&1; then
    log "❌ Ошибка в конфигурации"
    exit 1
fi

log "✅ Конфигурация создана"

# =============================================================================
# СОЗДАНИЕ СЕРВИСА
# =============================================================================

log "🔧 Создание systemd сервиса..."

cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

log "✅ Сервис создан"

# =============================================================================
# НАСТРОЙКА ФАЕРВОЛА
# =============================================================================

log "🛡️ Настройка фаервола..."

ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow ssh >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

log "✅ Фаервол настроен"

# =============================================================================
# ЗАПУСК СЕРВИСА
# =============================================================================

log "🚀 Запуск Xray..."

systemctl enable xray
systemctl start xray

sleep 3

if systemctl is-active --quiet xray; then
    log "✅ Xray запущен успешно"
else
    log "❌ Ошибка запуска Xray"
    journalctl -u xray --no-pager -n 5
    exit 1
fi

# =============================================================================
# СОХРАНЕНИЕ КОНФИГУРАЦИИ
# =============================================================================

log "💾 Сохранение конфигурации..."

# Сохранение для скриптов
cat > /root/reality_config.env << EOF
SERVER_IP=$SERVER_IP
UUID=$UUID
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
EOF

# Информация для пользователя
cat > /root/reality_info.txt << EOF
=== REALITY VPN СЕРВЕР ===
Дата: $(date)
IP: $SERVER_IP
Порт: 443

=== ДАННЫЕ ДЛЯ КЛИЕНТОВ ===
UUID: $UUID
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
SNI: www.microsoft.com
EOF

log "✅ Конфигурация сохранена"

# =============================================================================
# СОЗДАНИЕ QR-КОДА
# =============================================================================

log "📱 Создание QR-кода..."

VLESS_URL="vless://$UUID@$SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Reality-VPN"

echo "$VLESS_URL" | qrencode -t ansiutf8 > /root/qr_code.txt 2>/dev/null || true
echo "$VLESS_URL" > /root/vless_url.txt

log "✅ QR-код создан"

# =============================================================================
# СОЗДАНИЕ КЛИЕНТСКОГО СКРИПТА
# =============================================================================

log "💻 Создание скрипта для клиента..."

cat > /root/client_setup.sh << 'CLIENTSCRIPT'
#!/bin/bash

echo "💻 REALITY CLIENT SETUP"
echo "======================="

if [[ $EUID -ne 0 ]]; then
   echo "❌ Запустите с правами root: sudo bash $0"
   exit 1
fi

# Получение данных
echo "Введите данные REALITY сервера:"
read -p "IP сервера: " SERVER_IP
read -p "UUID: " UUID  
read -p "Public Key: " PUBLIC_KEY
read -p "Short ID: " SHORT_ID

echo "🧹 Очистка предыдущих установок..."
systemctl stop v2ray-client 2>/dev/null || true
rm -rf /etc/v2ray/ /usr/local/bin/v2ray 2>/dev/null || true
pkill -f v2ray 2>/dev/null || true

echo "📦 Установка v2ray..."
apt-get update -qq
apt-get install -y -qq wget unzip curl

cd /tmp
wget -q https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip
unzip -q v2ray-linux-64.zip
chmod +x v2ray
mv v2ray /usr/local/bin/
mkdir -p /etc/v2ray

echo "⚙️ Создание конфигурации..."
cat > /etc/v2ray/config.json << EOF
{
  "inbounds": [
    {
      "port": 10808,
      "listen": "127.0.0.1", 
      "protocol": "socks"
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
EOF

echo "🔧 Создание сервиса..."
cat > /etc/systemd/system/v2ray-client.service << EOF
[Unit]
Description=V2Ray Client
After=network.target

[Service]
User=nobody
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable v2ray-client
systemctl start v2ray-client

sleep 3
if systemctl is-active --quiet v2ray-client; then
    echo "✅ Клиент запущен"
    
    echo "🔍 Тест подключения..."
    timeout 10 curl --socks5 127.0.0.1:10808 -s https://httpbin.org/ip || echo "Тест не прошел"
    
    echo "🔄 Перезапуск n8n с прокси..."
    if command -v docker >/dev/null; then
        docker stop n8n 2>/dev/null || true
        docker run -d --name n8n \
          -p 5678:5678 \
          -v n8n_data:/home/node/.n8n \
          -e HTTP_PROXY=http://127.0.0.1:10809 \
          -e HTTPS_PROXY=http://127.0.0.1:10809 \
          --restart unless-stopped \
          docker.n8n.io/n8nio/n8n
        echo "✅ n8n перезапущен с прокси"
    fi
else
    echo "❌ Ошибка запуска клиента"
    systemctl status v2ray-client --no-pager
fi

echo ""
echo "🎉 НАСТРОЙКА ЗАВЕРШЕНА"
echo "Прокси: 127.0.0.1:10808 (SOCKS5), 127.0.0.1:10809 (HTTP)"
CLIENTSCRIPT

chmod +x /root/client_setup.sh

log "✅ Клиентский скрипт создан"

# =============================================================================
# ФИНАЛЬНЫЙ ВЫВОД
# =============================================================================

echo ""
echo "🎉 REALITY VPN СЕРВЕР УСТАНОВЛЕН!"
echo "================================="
echo ""
echo "📋 Информация:"
echo "   IP: $SERVER_IP"
echo "   Порт: 443"
echo "   UUID: $UUID"
echo "   Public Key: $PUBLIC_KEY"
echo "   Short ID: $SHORT_ID"
echo ""
echo "📱 QR-КОД ДЛЯ МОБИЛЬНЫХ:"
if [ -f /root/qr_code.txt ]; then
    cat /root/qr_code.txt
else
    echo "$VLESS_URL" | qrencode -t ansiutf8
fi
echo ""
echo "🔗 Ссылка для импорта:"
echo "$VLESS_URL"
echo ""
echo "📱 Приложения:"
echo "   Android: v2rayNG"
echo "   iOS: FairVPN, Shadowrocket"
echo ""
echo "💻 Для n8n сервера:"
echo "   1. Скопируйте файл: scp root@$SERVER_IP:/root/client_setup.sh ./"
echo "   2. Запустите: sudo bash client_setup.sh"
echo ""
echo "🔧 Управление:"
echo "   Статус: systemctl status xray"
echo "   Логи: journalctl -u xray -f"
echo "   Конфиг: /etc/xray/config.json"
echo ""
echo "✅ Сервер готов к подключениям!"
