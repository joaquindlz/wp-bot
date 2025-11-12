ARG BUILD_FROM
FROM $BUILD_FROM

RUN apt-get update && apt-get install -y \
    gnupg2 \
    bc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

######################################################################################################################
# FROM: https://github.com/nodejs/docker-node/blob/ba2b3e61e6aaf4643108fb5f1cda9ee5238efde5/18/bookworm/Dockerfile   #
######################################################################################################################

RUN groupadd --gid 1000 node \
  && useradd --uid 1000 --gid node --shell /bin/bash --create-home node

ENV NODE_VERSION 18.20.8

RUN ARCH= && dpkgArch="$(dpkg --print-architecture)" \
  && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86';; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  # use pre-existing gpg directory, see https://github.com/nodejs/docker-node/pull/1895#issuecomment-1550389150
  && export GNUPGHOME="$(mktemp -d)" \
  # gpg keys listed at https://github.com/nodejs/node#release-keys
  && set -ex \
  && for key in \
    C0D6248439F1D5604AAFFB4021D900FFDB233756 \
    DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7 \
    CC68F5A3106FF448322E48ED27F5E38D5B0A215F \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
    890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
    C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
    108F52B48DB57BB0CC439B2997B01419BD92F80A \
    A363A499291CBBC940DD62E41F10027AF002F8B0 \
  ; do \
      gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
      gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
  done \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
  && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
  && gpgconf --kill all \
  && rm -rf "$GNUPGHOME" \
  && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
  && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  # smoke tests
  && node --version \
  && npm --version

ENV YARN_VERSION 1.22.22

RUN set -ex \
  # use pre-existing gpg directory, see https://github.com/nodejs/docker-node/pull/1895#issuecomment-1550389150
  && export GNUPGHOME="$(mktemp -d)" \
  && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
  ; do \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
  done \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && gpgconf --kill all \
  && rm -rf "$GNUPGHOME" \
  && mkdir -p /opt \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  # smoke test
  && yarn --version \
  && rm -rf /tmp/*


######################################################################################################################
# FROM: https://github.com/joaquindlz/wp-bot/blob/main/Dockerfile                                                    #
######################################################################################################################

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
    && chown -R pptruser:pptruser /usr/src/app \
    # Dar permisos al script de healthcheck
    && chmod +x /usr/src/app/healthcheck.sh

# Cambiar al usuario no-root
#USER pptruser

# Establecer la ruta ejecutable de Chromium para Puppeteer vía variable de entorno
# whatsapp-web.js puede que la detecte automáticamente, pero ser explícito es bueno.
# Asegúrate que tu configuración en bot.js NO sobreescriba esto innecesariamente.
# La ruta '/usr/bin/chromium' es la estándar en Debian para el paquete 'chromium'.
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Expone un puerto si tu app lo necesitara (no es el caso del bot, pero es buena práctica documentarlo)
# EXPOSE 8080

# Healthcheck completo con detección de sesión caducada
# Verifica: proceso + sesión WhatsApp + Chromium + memoria
# CRÍTICO: Falla si la sesión de WhatsApp caduca o se desconecta
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD /usr/src/app/healthcheck.sh

# Comando por defecto para ejecutar la aplicación
# Se espera que la API_ENDPOINT y TARGET_GROUP_NAME se pasen como argumentos al ejecutar 'docker run'
# Ejemplo: docker run <imagename> https://miapi.com "Mi Grupo WhatsApp"
#ENTRYPOINT ["node", "bot.js"]

# Puedes poner valores por defecto o placeholders aquí si quieres
#CMD [$WEBHOOK_API, $TARGET_GROUP_NAME]

# FIXED: Changed from bashio to bash (bashio is not installed)
ENTRYPOINT ["/bin/bash", "/usr/src/app/run.sh"]
