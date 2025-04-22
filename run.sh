#!/usr/bin/env bashio

CONFIG_PATH=/usr/src/app/.wwebjs_auth/options.json

WEBHOOK_API=$(bashio::config 'webhookApi')
API_TOKEN=$(bashio::config 'apiToken')

bashio::log.info "WEBHOOK_API: ${WEBHOOK_API}"

/usr/local/bin/node /usr/src/app/bot.js "${WEBHOOK_API}" "${API_TOKEN}"
