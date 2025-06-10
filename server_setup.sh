#!/bin/bash

# =============================================================================
# СКРИПТ 1: АВТОМАТИЧЕСКАЯ НАСТРОЙКА СЕРВЕРА REALITY
# Сохраните как: server_setup.sh
# Запуск: bash server_setup.sh
# =============================================================================

echo "🚀 Автоматическая настройка REALITY сервера"
echo "============================================="

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Запустите скрипт с правами root: sudo bash server_setup.sh"
   exit 1
fi

# Обновление системы
echo "📦 Обновление системы..."
apt update && apt upgrade -y
apt install wget unzip curl qrencode -y

# Настройка времени
echo "⏰ Настройка времени..."
timedatectl set-timezone UTC

# Получение внешнего IP
SERVER_IP=$(curl -s ifconfig.me)
echo "🌐 Внешний IP сервера: $SERVER_IP"

# Установка Xray
echo "⬬ Установка Xray..."
cd /tmp
wget -q https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip -q Xray-linux-64.zip
chmod +x xray
mv xray /usr/local/bin/
mkdir -p /etc/xray
rm -f Xray-linux-64.zip

# Генерация ключей
echo "🔑 Генерация ключей..."
UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 4)

# Сохранение ключей
cat > /root/reality_config.txt << EOF
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
EOF

echo "💾 Конфигурация сохранена в /root/reality_config.txt"

# Создание конфигурации сервера
echo "⚙️ Создание конфигурации сервера..."
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

# Настройка фаервола
echo "🛡️ Настройка фаервола..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 443/tcp
ufw --force enable

# Запуск сервиса
echo "🚀 Запуск Xray сервиса..."
systemctl daemon-reload
systemctl enable xray
systemctl start xray

# Проверка статуса
sleep 3
if systemctl is-active --quiet xray; then
    echo "✅ Xray сервис запущен успешно!"
else
    echo "❌ Ошибка запуска Xray сервиса!"
    systemctl status xray
    exit 1
fi

# Создание QR кода для мобильных устройств
echo "📱 Создание QR кода для мобильных устройств..."
VLESS_URL="vless://$UUID@$SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#Reality-Server"

echo "$VLESS_URL" | qrencode -t ansiutf8
echo ""
echo "📱 Ссылка для импорта в мобильные приложения:"
echo "$VLESS_URL"

# Создание скрипта для клиента
echo "💻 Создание скрипта для клиента..."
cat > /root/client_setup.sh << 'EOF'
#!/bin/bash

# =============================================================================
# СКРИПТ 2: АВТОМАТИЧЕСКАЯ НАСТРОЙКА КЛИЕНТА REALITY
# Скопируйте этот файл на сервер с n8n и запустите
# =============================================================================

echo "💻 Автоматическая настройка REALITY клиента"
echo "============================================"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Запустите скрипт с правами root: sudo bash client_setup.sh"
   exit 1
fi

# Конфигурация (АВТОМАТИЧЕСКИ ПОДСТАВЛЯЕТСЯ)
SERVER_IP="SERVER_IP_PLACEHOLDER"
UUID="UUID_PLACEHOLDER"
PUBLIC_KEY="PUBLIC_KEY_PLACEHOLDER"
SHORT_ID="SHORT_ID_PLACEHOLDER"

echo "🔗 Подключение к серверу: $SERVER_IP"

# Установка v2ray
echo "⬬ Установка v2ray..."
cd /tmp
wget -q https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip
unzip -q v2ray-linux-64.zip
chmod +x v2ray
mv v2ray /usr/local/bin/
mkdir -p /etc/v2ray
rm -f v2ray-linux-64.zip

# Создание конфигурации клиента
echo "⚙️ Создание конфигурации клиента..."
cat > /etc/v2ray/config.json << CLIENTEOF
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
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "settings": {
        "auth": "noauth",
        "udp": false
      }
    },
    {
      "tag": "http",
      "port": 10809,
      "listen": "127.0.0.1",
      "protocol": "http",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
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
          "shortId": "$SHORT_ID",
          "spiderX": ""
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "outboundTag": "direct",
        "ip": [
          "geoip:private"
        ]
      }
    ]
  }
}
CLIENTEOF

# Создание systemd сервиса для клиента
echo "🔧 Создание systemd сервиса для клиента..."
cat > /etc/systemd/system/v2ray-client.service << SERVICEEOF
[Unit]
Description=V2Ray Client Service
Documentation=https://github.com/v2fly
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Запуск клиента
echo "🚀 Запуск v2ray клиента..."
systemctl daemon-reload
systemctl enable v2ray-client
systemctl start v2ray-client

# Проверка статуса
sleep 3
if systemctl is-active --quiet v2ray-client; then
    echo "✅ V2Ray клиент запущен успешно!"
else
    echo "❌ Ошибка запуска v2ray клиента!"
    systemctl status v2ray-client
    exit 1
fi

# Тест подключения
echo "🔍 Тест подключения..."
timeout 10 curl --socks5 127.0.0.1:10808 -s https://httpbin.org/ip > /tmp/proxy_test.json
if [ $? -eq 0 ]; then
    PROXY_IP=$(cat /tmp/proxy_test.json | grep -o '"origin": "[^"]*' | cut -d'"' -f4)
    echo "✅ Прокси работает! Ваш IP через прокси: $PROXY_IP"
else
    echo "❌ Ошибка подключения к прокси!"
fi

# Остановка старого n8n и запуск с прокси
echo "🔄 Перезапуск n8n с прокси..."
docker stop n8n 2>/dev/null || true
docker rm n8n 2>/dev/null || true

docker run -it -d --name n8n \
  -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e HTTP_PROXY=http://127.0.0.1:10809 \
  -e HTTPS_PROXY=http://127.0.0.1:10809 \
  -e NO_PROXY=localhost,127.0.0.1 \
  --add-host=host.docker.internal:host-gateway \
  docker.n8n.io/n8nio/n8n

echo "🎉 Готово! n8n перезапущен с REALITY прокси"
echo "📱 Веб-интерфейс n8n: http://$(curl -s ifconfig.me):5678"

# Создание команд для управления
cat > /root/reality_commands.sh << COMMANDSEOF
#!/bin/bash
# Полезные команды для управления REALITY

echo "=== КОМАНДЫ УПРАВЛЕНИЯ REALITY ==="
echo "1. Статус клиента: systemctl status v2ray-client"
echo "2. Логи клиента: journalctl -u v2ray-client -f"
echo "3. Перезапуск клиента: systemctl restart v2ray-client"
echo "4. Тест прокси: curl --socks5 127.0.0.1:10808 https://httpbin.org/ip"
echo "5. Перезапуск n8n: docker restart n8n"
echo "6. Логи n8n: docker logs n8n -f"
COMMANDSEOF

chmod +x /root/reality_commands.sh
echo "📋 Команды управления сохранены в /root/reality_commands.sh"
EOF

# Подстановка реальных значений в скрипт клиента
sed -i "s/SERVER_IP_PLACEHOLDER/$SERVER_IP/g" /root/client_setup.sh
sed -i "s/UUID_PLACEHOLDER/$UUID/g" /root/client_setup.sh
sed -i "s/PUBLIC_KEY_PLACEHOLDER/$PUBLIC_KEY/g" /root/client_setup.sh
sed -i "s/SHORT_ID_PLACEHOLDER/$SHORT_ID/g" /root/client_setup.sh
chmod +x /root/client_setup.sh

echo ""
echo "🎉 СЕРВЕР НАСТРОЕН УСПЕШНО!"
echo "=========================="
echo "📋 Информация сохранена в: /root/reality_config.txt"
echo "💻 Скрипт для клиента: /root/client_setup.sh"
echo ""
echo "📱 QR-код выше можно сканировать в мобильных приложениях:"
echo "   - Android: v2rayNG"
echo "   - iOS: FairVPN, Shadowrocket"
echo ""
echo "🔄 СЛЕДУЮЩИЙ ШАГ:"
echo "   1. Скопируйте файл /root/client_setup.sh на сервер с n8n"
echo "   2. Запустите: sudo bash client_setup.sh"
echo ""
echo "🔗 Или вручную используйте эти данные:"
cat /root/reality_config.txt
echo ""
echo "🎯 Сервер готов к подключениям!"

# =============================================================================
# ДОПОЛНИТЕЛЬНЫЙ СКРИПТ 3: БЫСТРАЯ ДИАГНОСТИКА
# Сохраните как: reality_check.sh
# =============================================================================

cat > /root/reality_check.sh << 'EOF'
#!/bin/bash

echo "🔍 ДИАГНОСТИКА REALITY"
echo "====================="

echo "1. 🖥️ Статус сервера Xray:"
systemctl status xray --no-pager -l

echo ""
echo "2. 🔗 Порт 443 (должен слушать Xray):"
netstat -tlnp | grep :443

echo ""
echo "3. 📊 Последние подключения:"
journalctl -u xray --since "10 minutes ago" --no-pager

echo ""
echo "4. 🌐 Внешний IP сервера:"
curl -s ifconfig.me

echo ""
echo "5. ⏰ Время сервера:"
date

echo ""
echo "6. 🔥 Фаервол (UFW) статус:"
ufw status

echo ""
echo "7. 💾 Конфигурация:"
if [ -f /root/reality_config.txt ]; then
    cat /root/reality_config.txt
else
    echo "❌ Файл конфигурации не найден!"
fi
EOF

chmod +x /root/reality_check.sh
echo "🔍 Скрипт диагностики создан: /root/reality_check.sh"
