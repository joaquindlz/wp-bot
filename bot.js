/**
 * WhatsApp Bot que escucha mensajes en un grupo específico
 * y envía los detalles a una API externa vía HTTP POST.
 * Diseñado para ejecutarse en un servidor headless / Docker.
 */

const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const axios = require('axios');

// --- Configuración ---
// Recibe la URL de la API y el nombre del grupo desde los argumentos de la línea de comandos
const API_ENDPOINT = process.argv[2];
const TARGET_GROUP_NAME = process.argv[3];
// Directorio para guardar los datos de la sesión DENTRO del contenedor/entorno
const SESSION_DATA_PATH = '/usr/src/app/.wwebjs_auth'; // Coincide con el punto de montaje del volumen Docker
// --------------------

// Validar argumentos de entrada
if (!API_ENDPOINT || !TARGET_GROUP_NAME) {
    console.error("Error: Debes proporcionar la URL de la API y el nombre del grupo como argumentos.");
    console.error("Ejemplo: node bot.js https://tu-api.com/endpoint \"Nombre Exacto Del Grupo\"");
    process.exit(1); // Salir si faltan argumentos
}

console.log(`--- Iniciando WhatsApp Bot ---`);
console.log(`API Endpoint: ${API_ENDPOINT}`);
console.log(`Grupo objetivo: "${TARGET_GROUP_NAME}"`);
console.log(`Ruta de datos de sesión: ${SESSION_DATA_PATH}`);
console.log(`-----------------------------`);

// Usar LocalAuth para guardar la sesión y no escanear QR cada vez
// Especificar dataPath es crucial para el mapeo de volúmenes en Docker
const client = new Client({
    authStrategy: new LocalAuth({
        dataPath: SESSION_DATA_PATH
    }),
    puppeteer: {
        headless: true, // ¡Esencial para servidores sin GUI!
        // executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || undefined, // Opcional: Usar path de env si está definido (p.ej., en Dockerfile)
                                                                          // Si no está definido, puppeteer intentará encontrar uno.
                                                                          // El Dockerfile instala chromium, así que debería encontrarlo.
        args: [
            '--no-sandbox', // Requerido en muchos entornos Linux/Docker
            '--disable-setuid-sandbox', // Requerido en muchos entornos Linux/Docker
            '--disable-dev-shm-usage', // Evita problemas con memoria compartida limitada en Docker
            '--disable-accelerated-2d-canvas', // Deshabilita aceleración por GPU (no necesaria en headless)
            '--no-first-run', // Evita pantallas de bienvenida de Chromium
            '--no-zygote', // Mejora la compatibilidad en algunos sistemas
            '--disable-gpu' // Otra forma de asegurar que la GPU no se use
            // '--single-process', // ¡Usar con precaución! Solo si hay problemas severos de memoria, puede causar inestabilidad.
        ],
    }
});

let targetGroupId = null; // Variable para almacenar el ID del grupo encontrado

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
    console.log('[AUTH] Autenticado exitosamente.');
});

// Evento: Fallo en la autenticación
client.on('auth_failure', msg => {
    console.error('[AUTH ERROR] Fallo en la autenticación:', msg);
    console.error('Asegúrate de que no haya otra sesión activa con el mismo dataPath.');
    console.error('Si el problema persiste, elimina el directorio de sesión y reintenta el escaneo QR.');
    process.exit(1); // Salir en caso de fallo crítico de autenticación
});

// Evento: El cliente está listo para usarse
client.on('ready', async () => {
    console.log('[READY] Cliente de WhatsApp listo!');
    console.log(`Buscando el grupo: "${TARGET_GROUP_NAME}"...`);

    try {
        const chats = await client.getChats();
        const group = chats.find(chat => chat.isGroup && chat.name === TARGET_GROUP_NAME);

        if (group) {
            targetGroupId = group.id._serialized; // Guardar el ID serializado del grupo
            console.log(`[GROUP FOUND] Grupo "${TARGET_GROUP_NAME}" encontrado. ID: ${targetGroupId}`);
            console.log(`Escuchando nuevos mensajes en este grupo...`);
        } else {
            console.error(`[ERROR] Grupo "${TARGET_GROUP_NAME}" NO encontrado.`);
            console.error('Verifica lo siguiente:');
            console.error('  1. El nombre del grupo es EXACTAMENTE el mismo (sensible a mayúsculas/minúsculas y emojis).');
            console.error('  2. El bot (número vinculado) es miembro del grupo.');
            console.error('  3. La sesión de WhatsApp está completamente cargada (puede tardar unos segundos después de "ready").');
            // Podrías decidir salir o seguir intentando encontrarlo en intervalos, pero salir es más simple.
            // await client.destroy(); // Limpiar antes de salir
            // process.exit(1);
            console.warn('El bot continuará ejecutándose, pero no procesará mensajes hasta que se encuentre el grupo (si aparece más tarde, no lo detectará sin reiniciar o lógica adicional).');
        }
    } catch (error) {
        console.error("[ERROR] Error buscando los chats o el grupo:", error);
    }
});

// Evento: Se crea/recibe un mensaje
// Usamos 'message_create' ya que captura los mensajes enviados por otros y por el propio bot (que filtraremos)
client.on('message_create', async (message) => {
    // Validar si tenemos el ID del grupo y si el mensaje pertenece a ese grupo
    if (targetGroupId && message.id.remote === targetGroupId) {

        // Ignorar mensajes enviados por el propio bot para evitar bucles o spam a la API
        if (message.fromMe) {
            // console.log(`[MSG IGNORED] Mensaje propio en "${TARGET_GROUP_NAME}"`);
            return;
        }

        console.log(`\n[NEW MSG] Nuevo mensaje recibido en "${TARGET_GROUP_NAME}"`);

        try {
            // Obtener información del contacto que envió el mensaje
            const contact = await message.getContact();
            // Intentar obtener el nombre más descriptivo posible
            const senderName = contact.pushname || contact.name || message.author || message.from;

            // Preparar el payload para enviar a la API
            const payload = {
                messageId: message.id.id,
                timestamp: message.timestamp, // Unix timestamp (segundos)
                receivedAt: Math.floor(Date.now() / 1000), // Timestamp de procesamiento (segundos)
                groupId: targetGroupId,
                groupName: TARGET_GROUP_NAME, // Ya lo tenemos, no es necesario obtenerlo del chat cada vez
                sender: {
                   id: message.author || message.from, // ID del remitente (ej: 1234567890@c.us)
                   name: senderName, // Nombre obtenido del contacto
                   isMe: message.fromMe // Booleano (siempre será false aquí por el filtro previo)
                },
                message: {
                   body: message.body, // Contenido del texto del mensaje
                   type: message.type, // Tipo de mensaje (chat, image, video, sticker, etc.)
                   hasMedia: message.hasMedia, // Booleano si tiene adjuntos
                   // Opcional: Añadir más detalles si son necesarios
                   // mediaKey: message.mediaKey,
                   // mentionedIds: message.mentionedIds,
                   // location: message.location, // Si es un mensaje de ubicación
                }
            };

            console.log('[API SEND] Enviando datos a:', API_ENDPOINT);
            // console.log('[API PAYLOAD]', JSON.stringify(payload, null, 2)); // Descomentar para depurar el payload completo

            // Realizar la petición HTTP POST a la API configurada
            axios.post(API_ENDPOINT, payload, { timeout: 10000 }) // Timeout de 10 segundos
                .then(response => {
                    console.log(`[API SUCCESS] Respuesta de API: Status ${response.status}`);
                    // console.log('[API RESPONSE DATA]', response.data); // Descomentar si necesitas ver la respuesta de la API
                })
                .catch(error => {
                    console.error('[API ERROR] Error al enviar datos a la API:');
                    if (error.response) {
                        // El servidor respondió con un status fuera del rango 2xx
                        console.error(`  Status: ${error.response.status}`);
                        console.error(`  Headers: ${JSON.stringify(error.response.headers)}`);
                        console.error(`  Data: ${JSON.stringify(error.response.data)}`);
                    } else if (error.request) {
                        // La petición se hizo pero no se recibió respuesta (ej. timeout, sin conexión)
                        console.error('  No se recibió respuesta del servidor.');
                        console.error(`  Request details: ${error.message}`);
                    } else {
                        // Algo ocurrió al configurar la petición que disparó un Error
                        console.error('  Error en configuración de Axios:', error.message);
                    }
                });

        } catch (error) {
            console.error("[ERROR] Error procesando el mensaje o contactando la API:", error);
        }
    }
    // Opcional: Loggear otros mensajes para depuración
    // else {
    //    const chat = await message.getChat();
    //    if (chat.isGroup) {
    //        console.log(`[DEBUG MSG] Mensaje de ${message.from} en otro grupo (${chat.name}): ${message.body}`);
    //    } else {
    //         console.log(`[DEBUG MSG] Mensaje privado de ${message.from}: ${message.body}`);
    //    }
    // }
});

// Evento: El cliente se desconecta
client.on('disconnected', (reason) => {
    console.warn('[DISCONNECTED] Cliente de WhatsApp desconectado:', reason);
    console.warn('El bot intentará reconectar automáticamente si es posible, pero si la sesión es inválida, puede requerir re-escanear el QR.');
    // Considerar salir si la desconexión es irrecuperable (ej. 'NAVIGATION')
    if (reason === 'NAVIGATION') {
         console.error('Desconexión crítica (NAVIGATION). Saliendo.');
         process.exit(1);
    }
    // whatsapp-web.js puede intentar reconectar, no siempre es necesario salir aquí.
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
// Capturar señales de terminación (Ctrl+C, docker stop, etc.)
const handleShutdown = async (signal) => {
    console.log(`\n[SHUTDOWN] Recibida señal ${signal}. Cerrando cliente de WhatsApp...`);
    try {
        await client.destroy();
        console.log('[SHUTDOWN] Cliente destruido limpiamente.');
    } catch (err) {
        console.error('[SHUTDOWN] Error al destruir el cliente:', err);
    } finally {
        process.exit(0); // Salir del proceso
    }
};

process.on('SIGINT', () => handleShutdown('SIGINT')); // Captura Ctrl+C
process.on('SIGTERM', () => handleShutdown('SIGTERM')); // Captura señales de terminación (ej. `docker stop`)
//
