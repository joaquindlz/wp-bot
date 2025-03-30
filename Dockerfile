# --- Stage 1: Build Environment ---
# Usar una imagen base oficial de Node.js (elige una versión LTS estable, ej. 18 o 20)
FROM node:18-bookworm AS base

# Establecer el directorio de trabajo dentro del contenedor
WORKDIR /usr/src/app

# Instalar dependencias del sistema necesarias para Puppeteer/Chromium en Debian (Bookworm)
# Incluimos chromium para tener una versión gestionada por el sistema
# Referencia: https://pptr.dev/troubleshooting#running-puppeteer-in-docker
RUN apt-get update && apt-get install -y \
    # --- Dependencias de Puppeteer ---
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libc6 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgbm1 \
    libgcc1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    lsb-release \
    wget \
    xdg-utils \
    # --- Instalar Chromium ---
    # Usar la versión del repo de Debian es más estable en Docker
    chromium \
    # --- Limpieza ---
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copiar SOLO los archivos de definición de paquetes
COPY package.json package-lock.json* ./

# Instalar dependencias de Node.js usando npm ci (más rápido y seguro para CI/CD y Docker)
# Omite devDependencies si las tienes y no las necesitas en producción
RUN npm ci --omit=dev --ignore-scripts

# Copiar el resto del código de la aplicación (respetará .dockerignore)
COPY . .

# --- Stage 2: Runtime Environment ---
# (Opcional, podríamos seguir usando la imagen 'base', pero esto es buena práctica si tuviéramos multi-stage complejo)
# En este caso, podemos simplificar y no usar multi-stage ya que necesitamos las herramientas de build y runtime juntas.

# Crear un usuario no-root para ejecutar la aplicación por seguridad
# 'pptruser' es el nombre que usa Puppeteer en su documentación de Docker
RUN groupadd -r pptruser && useradd -r -g pptruser -G audio,video pptruser \
    # Crear directorio home y darle permisos
    && mkdir -p /home/pptruser/Downloads \
    && chown -R pptruser:pptruser /home/pptruser \
    # Dar permisos al usuario sobre el directorio de la app
    && chown -R pptruser:pptruser /usr/src/app

# Cambiar al usuario no-root
USER pptruser

# Establecer la ruta ejecutable de Chromium para Puppeteer vía variable de entorno
# whatsapp-web.js puede que la detecte automáticamente, pero ser explícito es bueno.
# Asegúrate que tu configuración en bot.js NO sobreescriba esto innecesariamente.
# La ruta '/usr/bin/chromium' es la estándar en Debian para el paquete 'chromium'.
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Expone un puerto si tu app lo necesitara (no es el caso del bot, pero es buena práctica documentarlo)
# EXPOSE 8080

# Comando por defecto para ejecutar la aplicación
# Se espera que la API_ENDPOINT y TARGET_GROUP_NAME se pasen como argumentos al ejecutar 'docker run'
# Ejemplo: docker run <imagename> https://miapi.com "Mi Grupo WhatsApp"
ENTRYPOINT ["node", "bot.js"]

# Puedes poner valores por defecto o placeholders aquí si quieres
CMD ["YOUR_API_ENDPOINT_HERE", "YOUR_TARGET_GROUP_NAME_HERE"]
