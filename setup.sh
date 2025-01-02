#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <WEBSOCKET_URL>"
  exit 1
fi

DESTINATION=$1

echo "Updating and upgrading the server"
apt update && apt upgrade -y

echo "Creating SSL"
mkdir -p /etc/ssl/selfsigned/
cat <<EOF | tee /etc/ssl/selfsigned/openssl.cnf > /dev/null
[ req ]
default_bits        = 2048
default_md          = sha256
default_keyfile     = selfsigned.key
prompt              = no
encrypt_key         = no
distinguished_name  = req_distinguished_name

[ req_distinguished_name ]
C                   = US
ST                  = Washington
L                   = Washington District of Columbia
O                   = Puantum
OU                  = Puantum
CN                  = Puantum
emailAddress        = no@thanks.com
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/selfsigned/selfsigned.key \
    -out /etc/ssl/selfsigned/selfsigned.crt \
    -config /etc/ssl/selfsigned/openssl.cnf

echo "Installing Nginx"
apt install -y nginx

IPADDRESS=$(curl -s api.ipify.org)

echo "Configuring Nginx"
cat <<EOF | tee /etc/nginx/sites-available/default > /dev/null
server {
    listen 443 ssl http2;
    server_name $IPADDRESS;

    ssl_certificate_key /etc/ssl/selfsigned/selfsigned.key;
    ssl_certificate /etc/ssl/selfsigned/selfsigned.crt;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Frame-Options "SAMEORIGIN";

    gzip on;

    limit_req_zone \$binary_remote_addr zone=mylimit:60m rate=3r/s;

    location / {
        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ =404;
        location ~* \.(html|css|js)$ {
            expires 1d;
            add_header Cache-Control "public, must-revalidate, proxy-revalidate";
        }
    }

    location /websocket/ {
        proxy_redirect off;
        proxy_pass $DESTINATION;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_http_version 1.1;

        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$host;

        proxy_connect_timeout 1000;
        proxy_send_timeout 1000;
        proxy_read_timeout 1000;
    }

    error_page 404 /warning.html;
    location = /warning.html {
        root /var/www/html;
        internal;
    }

    error_page 500 502 503 504 /error.html;
    location = /error.html {
        root /var/www/html;
        internal;
    }

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;
}
EOF

echo "Restarting Nginx"
systemctl restart nginx

echo "Setup complete"
