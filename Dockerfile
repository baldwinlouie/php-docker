# Cloud Orchestrator Dockerfile
FROM php:8.1-apache-bullseye

RUN set -eux; \
  if command -v a2enmod; then \
    a2enmod rewrite; \
  fi; \
  savedAptMark="$(apt-mark showmanual)"

RUN set -eux; \
  apt-get update > /dev/null 2>&1 && \
  apt-get install -y --no-install-recommends \
    cron \
    git \
    libfreetype6-dev \
    libjpeg-dev \
    libmemcached-dev \
    libpng-dev \
    libzip-dev \
    mailutils  \
    mariadb-client \
    rsyslog \
    unzip \
    zip \
    zlib1g > /dev/null 2>&1

RUN set -eux; \
  HOSTNAME="$(hostname)"; \
  echo "postfix postfix/mailname string ${HOSTNAME}" | debconf-set-selections; \
  echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections; \
  DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes postfix > /dev/null 2>&1; \
  service rsyslog start; \
  service postfix restart > /dev/null 2>&1

# Install PHP libraries and etc.
RUN set -eux; \
  # Install APCu libraries.
  git clone https://github.com/krakjoe/apcu /usr/src/php/ext/apcu \
    && cd /usr/src/php/ext/apcu \
    && docker-php-ext-install apcu > /dev/null 2>&1; \
  \
  # Install OpCache.
  docker-php-ext-install -j "$(nproc)" opcache > /dev/null 2>&1; \
  \
  # Install uploadprogress.
  pecl install uploadprogress > /dev/null 2>&1 \
    && docker-php-ext-enable uploadprogress > /dev/null 2>&1; \
  \
  # Install Memcached.
  git clone https://github.com/php-memcached-dev/php-memcached /usr/src/php/ext/memcached \
    && cd /usr/src/php/ext/memcached \
    && docker-php-ext-install memcached > /dev/null 2>&1; \
  \
  # Install graphic libraries and etc.
  docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg > /dev/null 2>&1; \
  \
  docker-php-ext-install -j "$(nproc)" \
    gd \
    pdo_mysql \
    zip > /dev/null 2>&1

# Install Command line tools.
RUN set -eux; \
  # Install Composer.
  curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer \
    && composer global require

# Cloud Orchestrator PHP configurations
RUN { \
  echo 'memory_limit = -1'; \
  echo 'max_execution_time = 600'; \
  echo 'max_input_time = 600'; \
  echo 'max_input_vars = 100000'; \
} > /usr/local/etc/php/conf.d/extras.ini

RUN { \
  echo '<VirtualHost *:80>'; \
  echo '  DocumentRoot /var/www/cloud_orchestrator/docroot'; \
  echo '  <Directory />'; \
  echo '    Options FollowSymLinks'; \
  echo '    AllowOverride None'; \
  echo '  </Directory>'; \
  echo '  <Directory /var/www/cloud_orchestrator/docroot>'; \
  echo '    Options FollowSymLinks MultiViews'; \
  echo '    AllowOverride All'; \
  echo '    order allow,deny'; \
  echo '    allow from all'; \
  echo '  </Directory>'; \
  echo '  ErrorLog /var/log/apache2/cloud_orchestrator.error.log'; \
  echo '  LogLevel warn'; \
  echo '  CustomLog /var/log/apache2/cloud_orchestrator.access.log combined'; \
  echo '</VirtualHost>'; \
} > /etc/apache2/sites-available/cloud_orchestrator.conf

# Symbolic links for log files so that we can check them by docker logs command.
RUN set -eux; \
  ln -s /dev/stdout /var/log/apache2/cloud_orchestrator.access.log; \
  ln -s /dev/stderr /var/log/apache2/cloud_orchestrator.error.log

RUN set -eux; \
  # Unlink default apache configurations.
  a2dissite 000-default; \
  a2dissite default-ssl.conf; \
  a2ensite cloud_orchestrator

RUN set -eux; \
  mkdir /var/www/cloud_orchestrator; \
  mkdir /var/www/cloud_orchestrator/files; \
  chown -R www-data:www-data /var/www/cloud_orchestrator/files; \
  chmod -R g+w /var/www/cloud_orchestrator/files

EXPOSE 80
WORKDIR /var/www/cloud_orchestrator
