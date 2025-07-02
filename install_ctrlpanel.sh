#!/bin/bash

# Скрипт для автоматической установки Ctrlpanel на Ubuntu 20.04
# Домен: my.yoogo.su
# ВНИМАНИЕ: Запускайте этот скрипт от имени пользователя с sudo-правами или от root.
# Скрипт установит все необходимые компоненты и настроит панель.

# --- Переменные ---
# Замените на ваш email для SSL сертификата
ADMIN_EMAIL="dani4reks@gmail.com"
# Домен, который будет использоваться для панели
DOMAIN="my.yoogo.su"
# Генерируем случайный пароль для базы данных
DB_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)
DB_USER="ctrlpaneluser"
DB_NAME="ctrlpanel"

# --- Функции ---
# Функция для вывода информационных сообщений
function print_info {
    echo -e "\n\e[34m[INFO]\e[0m $1"
}

# Функция для вывода сообщений об ошибках и завершения работы
function print_error {
    echo -e "\n\e[31m[ERROR]\e[0m $1"
    exit 1
}

# Функция для проверки и настройки брандмауэра UFW
function check_and_configure_firewall {
    print_info "Проверка и настройка брандмауэра UFW..."
    if command -v ufw &> /dev/null; then
        UFW_STATUS=$(sudo ufw status | grep "Status: active")
        if [[ "$UFW_STATUS" == *"Status: active"* ]]; then
            print_info "UFW активен. Проверка правил для портов 80, 443 и OpenSSH..."
            
            # Проверка и разрешение порта 80
            PORT_80_ALLOWED=$(sudo ufw status | grep -E "80\s+(ALLOW|ALLOW IN)")
            if [[ -z "$PORT_80_ALLOWED" ]]; then
                print_info "Порт 80 не разрешен. Добавление правила..."
                sudo ufw allow 80/tcp
                if [ $? -ne 0 ]; then print_error "Не удалось разрешить порт 80 в UFW."; fi
            else
                print_info "Порт 80 уже разрешен."
            fi

            # Проверка и разрешение порта 443
            PORT_443_ALLOWED=$(sudo ufw status | grep -E "443\s+(ALLOW|ALLOW IN)")
            if [[ -z "$PORT_443_ALLOWED" ]]; then
                print_info "Порт 443 не разрешен. Добавление правила..."
                sudo ufw allow 443/tcp
                if [ $? -ne 0 ]; then print_error "Не удалось разрешить порт 443 в UFW."; fi
            else
                print_info "Порт 443 уже разрешен."
            fi
            
            # Проверка и разрешение OpenSSH (чтобы не заблокировать себя)
            SSH_ALLOWED=$(sudo ufw status | grep -E "OpenSSH\s+ALLOW")
            if [[ -z "$SSH_ALLOWED" ]]; then
                print_info "OpenSSH не разрешен. Добавление правила..."
                sudo ufw allow OpenSSH
                if [ $? -ne 0 ]; then print_error "Не удалось разрешить OpenSSH в UFW."; fi
            else
                print_info "OpenSSH уже разрешен."
            fi

            print_info "Перезагрузка UFW для применения изменений..."
            sudo ufw reload
            print_info "UFW настроен."
        else
            print_info "UFW не активен. Продолжаем без настройки UFW."
        fi
    else
        print_info "UFW не установлен. Продолжаем без настройки UFW."
    fi
}


# --- Начало установки ---
print_info "Начало установки Ctrlpanel для домена $DOMAIN"
sleep 3

# --- 1. Установка зависимостей ---
print_info "Обновление системы и установка базовых зависимостей..."
sudo apt-get update
sudo apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg

# Добавление репозитория PHP
print_info "Добавление PPA для PHP 8.3..."
sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
if [ $? -ne 0 ]; then print_error "Не удалось добавить PPA для PHP."; fi

# Добавление репозитория Redis
print_info "Добавление репозитория Redis..."
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list

# Добавление репозитория MariaDB
print_info "Добавление репозитория MariaDB..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash
if [ $? -ne 0 ]; then print_error "Не удалось добавить репозиторий MariaDB."; fi

# Обновление списка пакетов после добавления репозиториев
print_info "Повторное обновление списка пакетов..."
sudo apt-get update

# Установка основных пакетов (добавлен ufw)
print_info "Установка PHP, MariaDB, Nginx, Redis, UFW и других утилит..."
sudo apt-get -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,redis} mariadb-server nginx git redis-server certbot python3-certbot-nginx ufw
if [ $? -ne 0 ]; then print_error "Произошла ошибка при установке пакетов."; fi

# Вызов функции настройки брандмауэра
check_and_configure_firewall

# Включение Redis
print_info "Включение и запуск службы Redis..."
sudo systemctl enable --now redis-server

# --- 2. Установка Composer ---
print_info "Установка Composer..."
if ! command -v composer &> /dev/null
then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
    if [ $? -ne 0 ]; then print_error "Не удалось установить Composer."; fi
else
    print_info "Composer уже установлен."
fi


# --- 3. Загрузка файлов панели ---
print_info "Создание директории и загрузка файлов Ctrlpanel..."
sudo mkdir -p /var/www/ctrlpanel
cd /var/www/ctrlpanel
sudo git clone https://github.com/Ctrlpanel-gg/panel.git .
if [ $? -ne 0 ]; then print_error "Не удалось загрузить файлы с GitHub."; fi


# --- 4. Настройка базы данных ---
print_info "Настройка базы данных MariaDB..."
# Запускаем MariaDB Secure Installation в неинтерактивном режиме
sudo mysql_secure_installation <<EOF

y
$DB_PASSWORD
$DB_PASSWORD
y
y
y
y
EOF

# Создаем пользователя и базу данных
sudo mysql -u root -p"$DB_PASSWORD" <<MYSQL_SCRIPT
CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
CREATE DATABASE $DB_NAME;
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
if [ $? -ne 0 ]; then print_error "Не удалось создать базу данных или пользователя."; fi
print_info "База данных '$DB_NAME' и пользователь '$DB_USER' успешно созданы."


# --- 5. Установка зависимостей Composer и настройка приложения ---
print_info "Установка зависимостей Composer..."
cd /var/www/ctrlpanel
sudo COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
if [ $? -ne 0 ]; then print_error "Ошибка при установке зависимостей Composer."; fi

print_info "Создание символической ссылки на хранилище..."
sudo php artisan storage:link
if [ $? -ne 0 ]; then print_error "Не удалось создать символическую ссылку."; fi


# --- 6. Настройка веб-сервера Nginx и SSL ---
print_info "Настройка Nginx и получение SSL-сертификата..."
# Удаляем конфигурацию по умолчанию Nginx
sudo rm -f /etc/nginx/sites-enabled/default

# Создаем начальный конфигурационный файл Nginx для домена
print_info "Создание начального конфигурационного файла Nginx для $DOMAIN..."
sudo tee /etc/nginx/sites-available/ctrlpanel.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/ctrlpanel/public;
    index index.php;

    access_log /var/log/nginx/ctrlpanel.app-access.log;
    error_log  /var/log/nginx/ctrlpanel.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Включаем конфигурацию
print_info "Включение конфигурации Nginx..."
sudo ln -s -f /etc/nginx/sites-available/ctrlpanel.conf /etc/nginx/sites-enabled/ctrlpanel.conf

# Проверяем и перезапускаем Nginx, чтобы он загрузил новую конфигурацию
print_info "Проверка и перезапуск Nginx перед получением SSL..."
sudo nginx -t
if [ $? -ne 0 ]; then print_error "Ошибка в конфигурации Nginx после создания начального файла."; fi
sudo systemctl restart nginx
if [ $? -ne 0 ]; then print_error "Не удалось перезапустить Nginx после создания начального файла."; fi


# Получаем SSL сертификат с повторными попытками
MAX_RETRIES=3
RETRY_DELAY=10
CERT_SUCCESS=false

for i in $(seq 1 $MAX_RETRIES); do
    print_info "Попытка $i из $MAX_RETRIES: Получение SSL-сертификата для $DOMAIN..."
    # Certbot теперь должен найти существующий server block и настроить его
    if sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL; then
        CERT_SUCCESS=true
        print_info "SSL-сертификат успешно получен и установлен!"
        break
    else
        print_info "Не удалось получить или установить SSL-сертификат. Повторная попытка через $RETRY_DELAY секунд..."
        sleep $RETRY_DELAY
    fi
done

if [ "$CERT_SUCCESS" = false ]; then
    print_error "Не удалось получить или установить SSL-сертификат после $MAX_RETRIES попыток. Убедитесь, что:\n" \
                "  - DNS A-запись для $DOMAIN указывает на IP этого сервера и полностью распространилась (что вы уже подтвердили).\n" \
                "  - Отсутствуют блокировки брандмауэром (например, UFW настроен правильно, как мы пытались сделать, или другие внешние брандмауэры).\n" \
                "  - Вы не превысили ограничения Let's Encrypt на количество запросов (подождите 1-2 часа и попробуйте снова).\n" \
                "  Пожалуйста, проверьте логи Certbot: /var/log/letsencrypt/letsencrypt.log для более подробной информации."
fi

# --- 7. Настройка прав доступа ---
print_info "Настройка прав доступа к файлам..."
sudo chown -R www-data:www-data /var/www/ctrlpanel/
sudo chmod -R 755 /var/www/ctrlpanel/storage/* /var/www/ctrlpanel/bootstrap/cache/


# --- 8. Настройка фоновых задач ---
print_info "Настройка обработчика очереди и cron..."

# Настройка cron
(sudo crontab -l 2>/dev/null; echo "* * * * * php /var/www/ctrlpanel/artisan schedule:run >> /dev/null 2>&1") | sudo crontab -
print_info "Задача cron добавлена."

# Создание службы systemd для обработчика очереди
print_info "Создание службы systemd для обработчика очереди..."
sudo tee /etc/systemd/system/ctrlpanel.service > /dev/null <<EOF
[Unit]
Description=Ctrlpanel Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/ctrlpanel/artisan queue:work --sleep=3 --tries=3
StartLimitBurst=0

[Install]
WantedBy=multi-user.target
EOF

# Включение и запуск службы
sudo systemctl enable --now ctrlpanel.service
print_info "Служба обработчика очереди включена и запущена."


# --- Завершение ---
print_info "\e[32mУстановка успешно завершена!\e[0m"
echo -e "----------------------------------------------------"
echo -e "Теперь вы можете перейти в браузере по адресу: \e[1mhttps://$DOMAIN\e[0m"
echo -e "Вам нужно будет завершить установку через веб-интерфейс."
echo -e ""
echo -e "Данные для подключения к базе данных:"
echo -e "  Хост:      \e[1m127.0.0.1\e[0m"
echo -e "  База данных: \e[1m$DB_NAME\e[0m"
echo -e "  Пользователь:  \e[1m$DB_USER\e[0m"
echo -e "  Пароль:    \e[1m$DB_PASSWORD\e[0m"
echo -e "----------------------------------------------------"
