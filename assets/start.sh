#!/bin/bash

set -e

sed -i "s/EMAIL_DELIVERY_METHOD/${EMAIL_DELIVERY_METHOD-test}/" ${APP_HOME}config/outgoing_mail.yml
sed -i "s/SMTP_ADDRESS/${SMTP_ADDRESS-localhost}/" ${APP_HOME}config/outgoing_mail.yml
sed -i "s/SMTP_PORT/${SMTP_PORT-25}/" ${APP_HOME}config/outgoing_mail.yml
sed -i "s/SMTP_USER/${SMTP_USER-}/" ${APP_HOME}config/outgoing_mail.yml
sed -i "s/SMTP_PASS/${SMTP_PASS-}/" ${APP_HOME}config/outgoing_mail.yml

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
