/**
 * WhatsApp Bot que escucha mensajes en CUALQUIER chat (grupo o privado)
 * y envía los detalles a una API externa vía HTTP POST con autenticación Bearer Token.
 * Diseñado para ejecutarse en un servidor headless / Docker.
 */

const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const axios = require('axios');

// --- Configuración ---
// Recibe la URL de la API y el Token desde los argumentos de la línea de comandos
const API_ENDPOINT = process.argv[2];
const API_AUTH_TOKEN = process.argv[3]; // El token es ahora el segundo argumento útil
// Directorio para guardar los datos de la sesión DENTRO del contenedor/entorno
const SESSION_DATA_PATH = '/usr/src/app/.wwebjs_auth'; // Coincide con el punto de montaje del volumen Docker
// --------------------

// Validar argumentos de entrada
if (!API_ENDPOINT || !API_AUTH_TOKEN) { // Solo validar los 2 argumentos necesarios
    console.error("Error: Debes proporcionar la URL de la API y el Token de Autenticación como argumentos.");
    console.error("Ejemplo: node bot.js https://tu-api.com/endpoint TU_BEARER_TOKEN");
    process.exit(1); // Salir si faltan argumentos
}

console.log(`--- Iniciando WhatsApp Bot ---`);
console.log(`API Endpoint: ${API_ENDPOINT}`);
console.log(`Token de Autenticación: [CONFIGURADO]`); // No mostrar el token real en los logs
console.log(`Ruta de datos de sesión: ${SESSION_DATA_PATH}`);
console.log(`Modo: Escuchando TODOS los chats entrantes.`);
console.log(`-----------------------------`);

// Usar LocalAuth para guardar la sesión y no escanear QR cada vez
// Especificar dataPath es crucial para el mapeo de volúmenes en Docker
const client = new Client({
    authStrategy: new LocalAuth({
        dataPath: SESSION_DATA_PATH
    }),
    puppeteer: {
        headless: true, // ¡Esencial para servidores sin GUI!
        args: [
            '--no-sandbox', // Requerido en muchos entornos Linux/Docker
            '--disable-setuid-sandbox', // Requerido en muchos entornos Linux/Docker
            '--disable-dev-shm-usage', // Evita problemas con memoria compartida limitada en Docker
            '--disable-accelerated-2d-canvas', // Deshabilita aceleración por GPU (no necesaria en headless)
            '--no-first-run', // Evita pantallas de bienvenida de Chromium
            '--no-zygote', // Mejora la compatibilidad en algunos sistemas
            '--disable-gpu' // Otra forma de asegurar que la GPU no se use
        ],
    }
});

// Evento: Se genera el código QR para la autenticación
client.on('qr', (qr) => {
    console.log('\n------------------------------------------------------');
    console.log('Escanea este código QR con WhatsApp en tu teléfono:');
    console.log('(Configuración > Dispositivos vinculados > Vincular dispositivo)');
    qrcode.generate(qr, { small: true });
    console.log('------------------------------------------------------\n');
});

// Evento: Autenticación exitosa
client.on('authenticated', () => {
    console.log('[AUTH] Autenticado exitosamente en WhatsApp.');
});

// Evento: Fallo en la autenticación
client.on('auth_failure', msg => {
    console.error('[AUTH ERROR] Fallo en la autenticación de WhatsApp:', msg);
    console.error('Asegúrate de que no haya otra sesión activa con el mismo dataPath.');
    console.error('Si el problema persiste, elimina el directorio de sesión y reintenta el escaneo QR.');
    process.exit(1);
});

// Evento: El cliente está listo para usarse
client.on('ready', async () => {
    console.log('[READY] Cliente de WhatsApp listo!');
    console.log(`Escuchando todos los mensajes entrantes...`);
});

// Evento: Se crea/recibe un mensaje
// Usamos 'message_create' ya que captura los mensajes enviados por otros y por el propio bot (que filtraremos)
client.on('message_create', async (message) => {

    // Ignorar mensajes enviados por el propio bot para evitar bucles o spam a la API
    if (message.fromMe) {
        // console.log(`[MSG IGNORED] Mensaje propio.`);
        return;
    }

    try {
        // Obtener información del chat donde se recibió el mensaje
        const chat = await message.getChat();
        const chatId = chat.id._serialized; // ID del chat (grupo o privado)
        const chatName = chat.name; // Nombre del grupo o del contacto (si es chat privado)
        const isGroup = chat.isGroup; // Booleano para saber si es un grupo

        console.log(`\n[NEW MSG] Nuevo mensaje recibido en ${isGroup ? 'grupo' : 'chat privado'} "${chatName}" (ID: ${chatId})`);

        // Obtener información del contacto que envió el mensaje
        const contact = await message.getContact();
        // Intentar obtener el nombre más descriptivo posible del remitente
        const senderName = contact.pushname || contact.name || message.author || message.from; // El ID (author/from) puede ser diferente al ID del chat si es un grupo

        // Preparar el payload para enviar a la API
        const payload = {
            messageId: message.id.id,
            timestamp: message.timestamp, // Unix timestamp (segundos) del mensaje
            receivedAt: Math.floor(Date.now() / 1000), // Timestamp de procesamiento (segundos)
            chat: { // Información del chat donde se recibió
                id: chatId,
                name: chatName,
                isGroup: isGroup
            },
            sender: { // Información del remitente
               id: message.author || message.from, // ID del remitente (ej: 1234567890@c.us o groupId_participantId@g.us)
               name: senderName, // Nombre obtenido del contacto
               isMe: message.fromMe // Booleano (siempre será false aquí por el filtro previo)
            },
            message: { // Contenido del mensaje
               body: message.body, // Contenido del texto del mensaje
               type: message.type, // Tipo de mensaje (chat, image, video, sticker, etc.)
               hasMedia: message.hasMedia, // Booleano si tiene adjuntos
            }
        };

        console.log('[API SEND] Enviando datos a:', API_ENDPOINT);
        // console.log('[API PAYLOAD]', JSON.stringify(payload, null, 2)); // Descomentar para depurar el payload completo

        // --- Configuración de Axios con el encabezado de Autorización ---
        const axiosConfig = {
            headers: {
                'Authorization': `Bearer ${API_AUTH_TOKEN}`, // Añadir el encabezado Bearer Token
                'Content-Type': 'application/json' // Especificar que enviamos JSON
            },
            timeout: 10000 // Timeout de 10 segundos
        };
        // ---------------------------------------------------------------

        // Realizar la petición HTTP POST a la API configurada con los headers
        axios.post(API_ENDPOINT, payload, axiosConfig)
            .then(response => {
                console.log(`[API SUCCESS] Respuesta de API: Status ${response.status}`);
            })
            .catch(error => {
                console.error('[API ERROR] Error al enviar datos a la API:');
                if (error.response) {
                    console.error(`  Status: ${error.response.status}`);
                    if (error.response.status === 401 || error.response.status === 403) {
                       console.error('  ¡Error de autenticación/autorización! Verifica el API_AUTH_TOKEN.');
                    }
                } else if (error.request) {
                    console.error('  No se recibió respuesta del servidor (Timeout o problema de red).');
                } else {
                    console.error('  Error en configuración de Axios:', error.message);
                }
            });

    } catch (error) {
        console.error("[ERROR] Error procesando el mensaje:", error);
        // Añadir más detalles si es posible, por ejemplo, el ID del mensaje que falló
        if(message && message.id) {
            console.error(`  Mensaje ID: ${message.id.id}`);
        }
    }
});

// Evento: El cliente se desconecta
client.on('disconnected', (reason) => {
    console.warn('[DISCONNECTED] Cliente de WhatsApp desconectado:', reason);
    if (reason === 'NAVIGATION') {
         console.error('Desconexión crítica (NAVIGATION). Saliendo.');
         process.exit(1);
    }
});

// Evento: Cambio en el estado de la conexión
client.on('change_state', state => {
    console.log('[STATE CHANGE] Estado del cliente:', state);
});

// --- Inicio de la aplicación ---
console.log("Inicializando cliente de WhatsApp...");
client.initialize()
    .then(() => console.log("Inicialización del cliente iniciada."))
    .catch(err => {
        console.error("Error fatal durante la inicialización:", err);
        process.exit(1);
    });

// --- Manejo de cierre limpio ---
const handleShutdown = async (signal) => {
    console.log(`\n[SHUTDOWN] Recibida señal ${signal}. Cerrando cliente de WhatsApp...`);
    try {
        await client.destroy();
        console.log('[SHUTDOWN] Cliente destruido limpiamente.');
    } catch (err) {
        console.error('[SHUTDOWN] Error al destruir el cliente:', err);
    } finally {
        process.exit(0);
    }
};

process.on('SIGINT', () => handleShutdown('SIGINT'));
process.on('SIGTERM', () => handleShutdown('SIGTERM'));
