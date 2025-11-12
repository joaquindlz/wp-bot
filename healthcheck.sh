#!/bin/bash
# Healthcheck script para WhatsApp Bot
# Verifica que el bot esté funcionando correctamente

# Verificar que el proceso de Node.js está corriendo
if ! pgrep -f "node.*bot.js" > /dev/null; then
    echo "ERROR: Proceso de Node.js no está corriendo"
    exit 1
fi

# Verificar que el archivo de sesión existe (indica que el bot se ha autenticado)
if [ -d "/usr/src/app/.wwebjs_auth" ]; then
    # Verificar que el directorio no está vacío
    if [ -z "$(ls -A /usr/src/app/.wwebjs_auth)" ]; then
        echo "WARNING: Directorio de sesión vacío - bot no autenticado aún"
        # No fallar si el bot está en período de inicio
        if [ -f "/tmp/bot-started" ] && [ $(($(date +%s) - $(stat -c %Y /tmp/bot-started))) -lt 120 ]; then
            echo "INFO: Bot en periodo de inicio, esperando autenticación"
            exit 0
        fi
    fi
fi

# Verificar que Chromium está corriendo (indica que Puppeteer está activo)
if ! pgrep -f "chromium" > /dev/null; then
    echo "WARNING: Chromium no está corriendo - posible problema con Puppeteer"
    # No es crítico inmediatamente, puede estar reiniciando
fi

# Verificar uso de memoria (alerta si usa más del 80%)
MEM_USAGE=$(ps aux | grep "node.*bot.js" | grep -v grep | awk '{print $4}')
if [ ! -z "$MEM_USAGE" ]; then
    if (( $(echo "$MEM_USAGE > 80" | bc -l) )); then
        echo "WARNING: Alto uso de memoria: ${MEM_USAGE}%"
    fi
fi

echo "OK: Bot funcionando correctamente"
exit 0