#!/bin/bash
set -e

MARKER="/home/vagrant/.provisioned"

#db=mysql
db=mariadb
#db=postgresql


root_pass="root_pw!"
app_db="pixelfed"
app_user="pixelfed"
app_pass="strong_password"

# SSL / Let's Encrypt configuration
# Set to "letsencrypt" for a real certificate (domain must be publicly reachable)
# Set to "selfsigned" for a local self-signed certificate (works offline / Vagrant)
ssl_mode="selfsigned"
app_domain="local.pixelfed.test"
letsencrypt_email=""   # required when ssl_mode=letsencrypt (e.g. "admin@pixelfed.dev")


# Fix: Force apt to use IPv4 to avoid TLS handshake errors with IPv6
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

echo "--- Updating package list ---"
apt-get update -y

echo "--- Installing prerequisites ---"
apt-get install -y lsb-release apt-transport-https ca-certificates wget curl gnupg2

echo "--- Adding Sury PHP 8.5 repository (packages.sury.org) ---"
wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
  > /etc/apt/sources.list.d/php.list

echo "--- Updating package list with new repo ---"
apt-get update -y

echo "--- Installing PHP 8.5 and Apache ---"
apt-get install -y php8.5 \
  libapache2-mod-php8.5 \
  apache2 \
  php8.5-fpm \
  php8.5-bcmath \
  php8.5-ctype \
  php8.5-curl \
  php8.5-exif \
  php8.5-gd \
  php8.5-iconv \
  php8.5-intl \
  php8.5-mbstring \
  php8.5-redis \
  php8.5-tokenizer \
  php8.5-xml \
  php8.5-zip \
  pngquant \
  ffmpeg \
  jpegoptim \
  redis \
  certbot \
  python3-certbot-apache

# install DB

if [ "$db" = "mysql" ]; then
  echo "--- Installing MySQL ---"
  apt-get install -y mysql-server mysql-client
  systemctl enable mysql
  systemctl start mysql
  apt-get install -y php8.5-mysql
elif [ "$db" = "mariadb" ]; then
  echo "--- Installing MariaDB ---"
  apt-get install -y mariadb-server mariadb-client
  systemctl enable mariadb
  systemctl start mariadb
  # pdo_mysql and mysqli are included in php8.5-mysql
  apt-get install -y php8.5-mysql
elif [ "$db" = "postgresql" ]; then
  echo "--- Installing PostgreSQL ---"
  apt-get install -y postgresql postgresql-client
  systemctl enable postgresql
  systemctl start postgresql
  # pdo_pgsql and pgsql are included in php8.5-pgsql
  apt-get install -y php8.5-pgsql
else
  echo "Error: db variable not set to a valid option (mysql, mariadb, postgresql)."
  exit 1
fi

# -------------------------------------------------------
# To install additional packages, add them here, e.g.:
#   apt-get install -y php8.5-mysql php8.5-curl php8.5-mbstring
# -------------------------------------------------------
echo "--- Enabling Apache and starting it ---"
systemctl enable apache2

echo "--- Enabling PHP-FPM with Apache ---"
a2enmod proxy_fcgi setenvif
a2enconf php8.5-fpm
ln -sf /usr/sbin/php-fpm8.5 /usr/local/bin/php-fpm

echo "--- Enabling Apache modules for SSL and rewrites ---"
a2enmod ssl rewrite headers

echo "--- Deploying Pixelfed Apache VirtualHost ---"
cp /var/www/html/pixelfed/env/pixelfed-apache.conf /etc/apache2/sites-available/pixelfed.conf
# Replace placeholder domain with configured domain
sed -i "s/local.pixelfed.test/$app_domain/g" /etc/apache2/sites-available/pixelfed.conf
a2ensite pixelfed.conf
a2dissite 000-default.conf

systemctl restart apache2

echo "--- Setting up SSL certificate ---"
if [ "$ssl_mode" = "letsencrypt" ]; then
    if [ -z "$letsencrypt_email" ]; then
        echo "ERROR: letsencrypt_email must be set when ssl_mode=letsencrypt"
        exit 1
    fi
    echo "--- Obtaining Let's Encrypt certificate for $app_domain ---"
    certbot --apache \
        --non-interactive \
        --agree-tos \
        --email "$letsencrypt_email" \
        --domains "$app_domain" \
        --redirect
    echo "--- Let's Encrypt certificate installed successfully ---"
else
    echo "--- Generating self-signed certificate for $app_domain ---"
    mkdir -p /etc/ssl/pixelfed
    if [ ! -f /etc/ssl/pixelfed/selfsigned.crt ]; then
        openssl req -x509 -nodes -days 3650 \
            -newkey rsa:2048 \
            -keyout /etc/ssl/pixelfed/selfsigned.key \
            -out /etc/ssl/pixelfed/selfsigned.crt \
            -subj "/C=US/ST=Dev/L=Local/O=Pixelfed/CN=$app_domain"
    fi

    # Create SSL VirtualHost for self-signed cert
    cat > /etc/apache2/sites-available/pixelfed-ssl.conf <<SSLEOF
<VirtualHost *:443>
    ServerName $app_domain

    DocumentRoot /var/www/html/pixelfed/public

    <Directory /var/www/html/pixelfed/public>
        AllowOverride All
        Require all granted
        Options -Indexes +FollowSymLinks
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/ssl/pixelfed/selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/pixelfed/selfsigned.key

    ErrorLog \${APACHE_LOG_DIR}/pixelfed-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/pixelfed-ssl-access.log combined
</VirtualHost>
SSLEOF
    a2ensite pixelfed-ssl.conf
    systemctl restart apache2
    echo "--- Self-signed certificate installed (browser will show a warning) ---"
fi

echo "--- PHP version installed ---"
php -v
php-fpm -v

echo "--- Provisioning complete! Visit https://$app_domain ---"


# Temporarily disable "exit on error" for the database setup block.
# We rely on try-without-password / try-with-password fallback logic,
# which is incompatible with set -e (the first failure would kill the script).
set +e

if [ "$db" = "mysql" ] || [ "$db" = "mariadb" ]; then
    # Wait for the database service to be fully ready
    echo "--- Waiting for database service to be ready ---"
    for i in $(seq 1 10); do
        mysqladmin ping --user=root --silent &>/dev/null && break
        mysqladmin ping --user=root --password="$root_pass" --silent &>/dev/null && break
        echo "Waiting for database... ($i/10)"
        sleep 2
    done

    # Helper: run a SQL statement as root.
    # Fresh install  → root uses unix_socket auth (no password).
    # Re-provision   → previous run already set a password, socket auth may
    #                   have been removed, so we fall back to password auth.
    mysql_root() {
        mysql --user=root -e "$1" &>/dev/null \
        || mysql --user=root --password="$root_pass" -e "$1" 2>/dev/null
    }

    # 1. Secure root account (set a native-password credential, keep socket auth on MariaDB)
    if [ "$db" = "mariadb" ]; then
        mysql_root "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('$root_pass');"
    else
        mysql_root "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$root_pass';"
    fi
    mysql_root "FLUSH PRIVILEGES;"

    # 2. Create App DB and User
    mysql_root "CREATE DATABASE IF NOT EXISTS $app_db;"
    mysql_root "CREATE USER IF NOT EXISTS '$app_user'@'localhost' IDENTIFIED BY '$app_pass';"
    mysql_root "GRANT ALL PRIVILEGES ON $app_db.* TO '$app_user'@'localhost';"
    mysql_root "FLUSH PRIVILEGES;"

    echo "--- MySQL/MariaDB setup complete ---"

elif [ "$db" = "postgresql" ]; then
    echo "--- Configuring PostgreSQL ---"

    # 1. Set 'postgres' (root-equivalent) password
    sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$root_pass';"

    # 2. Create App User with password
    # We query pg_roles first to check if the user exists to avoid an error
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$app_user'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER $app_user WITH ENCRYPTED PASSWORD '$app_pass';"

    # 3. Grant CREATEDB permission (often needed for frameworks like Rails/Pixelfed)
    sudo -u postgres psql -c "ALTER USER $app_user CREATEDB;"

    # 4. Create App Database and assign owner
    # We query pg_database first to check if DB exists
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$app_db'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE $app_db OWNER $app_user;"

    echo "--- PostgreSQL setup complete ---"
fi

# Re-enable exit-on-error for the rest of the script
set -e

# enable composer
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
php -r "unlink('composer-setup.php');"


cat >> /etc/redis/redis.conf <<'EOF'
port 6379
unixsocket /run/redis/redis.sock
unixsocketperm 770
EOF

cat >> /home/vagrant/.bashrc <<'EOF'
alias l='ls -alh'
alias e='exit'
alias pf='cd /var/www/html/pixelfed'
alias logs='sudo tail -f /var/log/apache2/*.log'
alias logs-app='tail -f /var/www/html/pixelfed/storage/logs/laravel.log'
alias logs-ssl='sudo tail -f /var/log/apache2/pixelfed-ssl-error.log'
EOF

cp /var/www/html/pixelfed/env/.env /var/www/html/pixelfed/.env
cp /var/www/html/pixelfed/env/pixelfed.service /etc/systemd/system/pixelfed.service
chown vagrant:vagrant /var/www/html/pixelfed/.env

cd /var/www/html/pixelfed
sudo find . -type d -exec chmod 755 {} \;
sudo find . -type d -exec chown vagrant:vagrant {} \;

sudo find . -type f -exec chmod 644 {} \;

composer install --no-ansi --no-interaction --optimize-autoloader

# set all files to user/group vagrant
sudo find . -type d -exec chown vagrant:vagrant {} \;
sudo find . -type f -exec chown vagrant:vagrant {} \;

if [ -f "$MARKER" ]; then
    echo "--- Already provisioned, skipping: everything from docs: https://docs.pixelfed.org/running-pixelfed/installation.html"

else
  # do this only once
  php artisan key:generate
  php artisan storage:link
  php artisan migrate --force
  php artisan import:cities
  php artisan instance:actor
  php artisan horizon:install
fi

# should always run:
php artisan route:cache
php artisan view:cache

# run this for every change in .env, also via vagrant ssh
php artisan config:cache

# does this have to run always? or just once?
php artisan horizon:publish


#set a marker to see that you already provisioned once
touch "$MARKER"

echo "visit http://192.168.56.20"
echo "visit https://$app_domain"
echo "--- Self-signed certificate - so your browser will show a warning ---"
