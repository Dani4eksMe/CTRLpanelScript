#!/bin/bash

# Скрипт для автоматической установки Ctrlpanel на Ubuntu 20.04
# Домен: my.yoogo.su
# ВНИМАНИЕ: Запускайте этот скрипт от имени пользователя с sudo-правами или от root.
# Скрипт установит все необходимые компоненты и настроит панель.

# --- Переменные ---
# Замените на ваш email для SSL сертификата
ADMIN_EMAIL="dani4eks@gmail.com"
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

# Функция для очистки установки
function cleanup_installation {
    print_info "Остановка служб..."
    sudo systemctl stop ctrlpanel.service 2>/dev/null
    sudo systemctl disable ctrlpanel.service 2>/dev/null
    sudo rm -f /etc/systemd/system/ctrlpanel.service 2>/dev/null
    sudo systemctl daemon-reload 2>/dev/null
    sudo systemctl stop nginx 2>/dev/null
    sudo systemctl stop mariadb 2>/dev/null
    sudo systemctl stop redis-server 2>/dev/null

    print_info "Удаление cron задачи..."
    (sudo crontab -l 2>/dev/null | grep -v "/var/www/ctrlpanel/artisan schedule:run") | sudo crontab - 2>/dev/null

    print_info "Удаление конфигураций Nginx и SSL-сертификатов..."
    sudo rm -f /etc/nginx/sites-enabled/ctrlpanel.conf 2>/dev/null
    sudo rm -f /etc/nginx/sites-available/ctrlpanel.conf 2>/dev/null
    # Удаляем SSL-сертификаты и связанные конфигурации Certbot
    sudo certbot delete --non-interactive --cert-name "$DOMAIN" 2>/dev/null

    print_info "Удаление базы данных и пользователя MariaDB..."
    # Убедимся, что MariaDB запущена для очистки
    sudo systemctl start mariadb 2>/dev/null
    if sudo mysql -u root -p"$DB_PASSWORD" -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null; then
        print_info "База данных '$DB_NAME' удалена."
    fi
    if sudo mysql -u root -p"$DB_PASSWORD" -e "DROP USER IF EXISTS '$DB_USER'@'127.0.0.1';" 2>/dev/null; then
        print_info "Пользователь базы данных '$DB_USER' удален."
    fi
    sudo systemctl stop mariadb 2>/dev/null


    print_info "Удаление директории приложения..."
    sudo rm -rf /var/www/ctrlpanel 2>/dev/null

    print_info "Удаление установленных пакетов..."
    # Список пакетов, которые могли быть установлены скриптом
    PACKAGES_TO_REMOVE="php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip php8.3-intl php8.3-redis mariadb-server nginx git redis-server certbot python3-certbot-nginx ufw composer"
    for pkg in $PACKAGES_TO_REMOVE; do
        if dpkg -s "$pkg" &>/dev/null; then # Проверяем, установлен ли пакет
            print_info "Удаление пакета: $pkg"
            sudo apt-get -y purge "$pkg" 2>/dev/null
        fi
    done
    sudo apt-get -y autoremove 2>/dev/null
    sudo apt-get -y clean 2>/dev/null

    print_info "Удаление добавленных PPA и репозиториев (если применимо, будьте осторожны)..."
    # Эта часть закомментирована, так как может быть слишком агрессивной, раскомментируйте, если действительно необходимо.
    # sudo add-apt-repository --remove ppa:ondrej/php -y 2>/dev/null
    # sudo rm -f /etc/apt/sources.list.d/redis.list 2>/dev/null
    # sudo rm -f /etc/apt/sources.list.d/mariadb.list 2>/dev/null
    # sudo apt-get update 2>/dev/null
}

# Функция для вывода сообщений об ошибках и завершения работы
function print_error {
    echo -e "\n\e[31m[ERROR]\e[0m $1" >&2 # Вывод в stderr
    echo -e "\n\e[31mУстановка не может быть продолжена из-за ошибки.\e[0m" >&2
    echo -e "Хотите ли вы очистить все, что было установлено скриптом до этого момента? (Нажмите ПРОБЕЛ для подтверждения, любую другую клавишу для выхода)"
    read -n 1 -s -r KEY # Читаем один символ без отображения
    echo # Новая строка после ввода
    if [[ "$KEY" == " " ]]; then
        print_info "Начало очистки..."
        cleanup_installation
        print_info "Очистка завершена. Выход."
    else
        print_info "Очистка отменена. Выход."
    fi
    exit 1
}


# --- Начало установки ---
print_info "Начало установки Ctrlpanel для домена $DOMAIN"
sleep 3

# --- 1. Установка зависимостей ---
print_info "Обновление системы и установка базовых зависимостей..."
sudo apt-get update || print_error "Не удалось обновить список пакетов."
sudo apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg || print_error "Не удалось установить базовые зависимости."

# Добавление репозитория PHP
print_info "Добавление PPA для PHP 8.3..."
sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php || print_error "Не удалось добавить PPA для PHP."

# Добавление репозитория Redis
print_info "Добавление репозитория Redis..."
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg || print_error "Не удалось добавить ключ GPG для Redis."
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list || print_error "Не удалось добавить репозиторий Redis."

# Добавление репозитория MariaDB
print_info "Добавление репозитория MariaDB..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash || print_error "Не удалось добавить репозиторий MariaDB."

# Обновление списка пакетов после добавления репозиториев
print_info "Повторное обновление списка пакетов и очистка кэша apt..."
sudo apt-get clean && sudo apt-get update || print_error "Не удалось повторно обновить список пакетов или очистить кэш apt."

# Установка основных пакетов (добавлен ufw)
print_info "Установка PHP, MariaDB, Nginx, Redis, UFW и других утилит..."
sudo apt-get -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,redis} mariadb-server nginx git redis-server certbot python3-certbot-nginx ufw || print_error "Произошла ошибка при установке PHP 8.3 или других пакетов. Проверьте правильность PPA и доступность пакетов."

# Вызов функции настройки брандмауэра
check_and_configure_firewall

# Включение Redis
print_info "Включение и запуск службы Redis..."
sudo systemctl enable --now redis-server || print_error "Не удалось включить и запустить службу Redis."

# --- 2. Установка Composer ---
print_info "Установка Composer..."
if ! command -v composer &> /dev/null
then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer || print_error "Не удалось установить Composer."
else
    print_info "Composer уже установлен."
fi


# --- 3. Загрузка файлов панели ---
print_info "Создание директории и загрузка файлов Ctrlpanel..."
sudo mkdir -p /var/www/ctrlpanel || print_error "Не удалось создать директорию /var/www/ctrlpanel."
cd /var/www/ctrlpanel || print_error "Не удалось перейти в директорию /var/www/ctrlpanel."
sudo git clone https://github.com/Ctrlpanel-gg/panel.git . || print_error "Не удалось загрузить файлы с GitHub."


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
if [ $? -ne 0 ]; then print_error "Ошибка при выполнении mysql_secure_installation."; fi

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
cd /var/www/ctrlpanel || print_error "Не удалось перейти в директорию /var/www/ctrlpanel для установки Composer зависимостей."
sudo COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader || print_error "Ошибка при установке зависимостей Composer."

print_info "Создание символической ссылки на хранилище..."
sudo php artisan storage:link || print_error "Не удалось создать символическую ссылку."


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
sudo nginx -t || print_error "Ошибка в конфигурации Nginx после создания начального файла."
sudo systemctl restart nginx || print_error "Не удалось перезапустить Nginx после создания начального файла."


# Получаем SSL сертификат с повторными попытками
MAX_RETRIES=3
RETRY_DELAY=10
CERT_SUCCESS=false

for i in $(seq 1 $MAX_RETRIES); do
    print_info "Попытка $i из $MAX_RETRIES: Получение SSL-сертификата для $DOMAIN..."
    # Certbot теперь должен найти существующий server block и настроить его
    if sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL"; then
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
sudo chown -R www-data:www-data /var/www/ctrlpanel/ || print_error "Не удалось изменить владельца директории /var/www/ctrlpanel/."
sudo chmod -R 755 /var/www/ctrlpanel/storage/* /var/www/ctrlpanel/bootstrap/cache/ || print_error "Не удалось настроить права доступа для директорий storage и bootstrap/cache."


# --- 8. Настройка фоновых задач ---
print_info "Настройка обработчика очереди и cron..."

# Настройка cron
(sudo crontab -l 2>/dev/null; echo "* * * * * php /var/www/ctrlpanel/artisan schedule:run >> /dev/null 2>&1") | sudo crontab - || print_error "Не удалось добавить задачу cron."
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
if [ $? -ne 0 ]; then print_error "Не удалось создать службу systemd для обработчика очереди."; fi

# Включение и запуск службы
sudo systemctl enable --now ctrlpanel.service || print_error "Не удалось включить и запустить службу обработчика очереди."
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
