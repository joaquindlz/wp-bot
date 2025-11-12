#!/bin/bash
# Healthcheck script para WhatsApp Bot
# Verifica que el bot esté funcionando correctamente incluyendo estado de sesión

# Archivo de estado de la sesión (actualizado por bot.js)
SESSION_STATE_FILE="/tmp/whatsapp-session-state"
SESSION_TIMEOUT=300  # 5 minutos - si no se actualiza en este tiempo, hay problemas

# Colores para logs (aunque Docker no los muestre, útil para debugging manual)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Función de logging
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# 1. Verificar que el proceso de Node.js está corriendo
if ! pgrep -f "node.*bot.js" > /dev/null; then
    log_error "Proceso de Node.js no está corriendo"
    exit 1
fi
log_success "Proceso de Node.js activo"

# 2. Verificar que Chromium está corriendo (indica que Puppeteer está activo)
if ! pgrep -f "chromium" > /dev/null; then
    log_warning "Chromium no está corriendo - posible problema con Puppeteer"
    # No es crítico inmediatamente, puede estar reiniciando
fi

# 3. CRÍTICO: Verificar estado de la sesión de WhatsApp
if [ -f "$SESSION_STATE_FILE" ]; then
    # Leer el estado de la sesión
    SESSION_STATE=$(cat "$SESSION_STATE_FILE")
    
    # Verificar edad del archivo (última actualización)
    CURRENT_TIME=$(date +%s)
    FILE_MOD_TIME=$(stat -c %Y "$SESSION_STATE_FILE" 2>/dev/null || stat -f %m "$SESSION_STATE_FILE" 2>/dev/null)
    TIME_DIFF=$((CURRENT_TIME - FILE_MOD_TIME))
    
    # Si el archivo no se ha actualizado en SESSION_TIMEOUT segundos, hay un problema
    if [ $TIME_DIFF -gt $SESSION_TIMEOUT ]; then
        log_error "Estado de sesión no actualizado en ${TIME_DIFF}s (límite: ${SESSION_TIMEOUT}s)"
        exit 1
    fi
    
    # Verificar el contenido del archivo de estado
    case "$SESSION_STATE" in
        "CONNECTED")
            log_success "WhatsApp conectado y activo"
            ;;
        "AUTHENTICATED")
            log_success "WhatsApp autenticado, conectando..."
            ;;
        "READY")
            log_success "WhatsApp listo y funcionando"
            ;;
        "QR")
            log_warning "Esperando escaneo de código QR"
            # Durante el período de inicio, esto es normal
            if [ -f "/tmp/bot-started" ]; then
                STARTED_TIME=$(stat -c %Y "/tmp/bot-started" 2>/dev/null || stat -f %m "/tmp/bot-started" 2>/dev/null)
                UPTIME=$((CURRENT_TIME - STARTED_TIME))
                if [ $UPTIME -gt 300 ]; then
                    # Más de 5 minutos esperando QR - posible problema
                    log_error "Esperando código QR por más de 5 minutos"
                    exit 1
                fi
            fi
            ;;
        "DISCONNECTED"|"SESSION_EXPIRED"|"LOGGED_OUT")
            log_error "Sesión de WhatsApp caducada o desconectada: $SESSION_STATE"
            exit 1
            ;;
        "AUTH_FAILURE")
            log_error "Fallo en autenticación de WhatsApp"
            exit 1
            ;;
        *)
            log_warning "Estado de sesión desconocido: $SESSION_STATE"
            ;;
    esac
else
    # Si el archivo no existe, verificar si el bot acaba de iniciar
    if [ -f "/tmp/bot-started" ]; then
        CURRENT_TIME=$(date +%s)
        STARTED_TIME=$(stat -c %Y "/tmp/bot-started" 2>/dev/null || stat -f %m "/tmp/bot-started" 2>/dev/null)
        UPTIME=$((CURRENT_TIME - STARTED_TIME))
        
        if [ $UPTIME -lt 120 ]; then
            # Menos de 2 minutos - período de inicio normal
            log_warning "Bot iniciando, esperando estado de sesión..."
            exit 0
        else
            # Más de 2 minutos sin archivo de estado - problema
            log_error "Archivo de estado de sesión no encontrado después de ${UPTIME}s"
            exit 1
        fi
    else
        log_error "Archivo de estado de sesión no encontrado y marca de inicio ausente"
        exit 1
    fi
fi

# 4. Verificar que el directorio de sesión existe y no está vacío
if [ -d "/usr/src/app/.wwebjs_auth" ]; then
    if [ -z "$(ls -A /usr/src/app/.wwebjs_auth)" ]; then
        log_warning "Directorio de sesión vacío - bot no autenticado aún"
        # Verificar si estamos en período de inicio
        if [ -f "/tmp/bot-started" ]; then
            CURRENT_TIME=$(date +%s)
            STARTED_TIME=$(stat -c %Y "/tmp/bot-started" 2>/dev/null || stat -f %m "/tmp/bot-started" 2>/dev/null)
            UPTIME=$((CURRENT_TIME - STARTED_TIME))
            if [ $UPTIME -gt 600 ]; then
                # Más de 10 minutos sin sesión - problema
                log_error "Sesión no establecida después de 10 minutos"
                exit 1
            fi
        fi
    else
        log_success "Directorio de sesión contiene datos"
    fi
else
    log_warning "Directorio de sesión no encontrado"
fi

# 5. Verificar uso de memoria (alerta si usa más del 80%)
MEM_USAGE=$(ps aux | grep "node.*bot.js" | grep -v grep | awk '{print $4}' | head -n1)
if [ ! -z "$MEM_USAGE" ]; then
    # Verificar si bc está disponible
    if command -v bc &> /dev/null; then
        if (( $(echo "$MEM_USAGE > 80" | bc -l) )); then
            log_warning "Alto uso de memoria: ${MEM_USAGE}%"
        fi
    fi
fi

log_success "Todos los checks pasaron correctamente"
exit 0