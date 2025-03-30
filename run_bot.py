import subprocess
import sys
import os

# --- Configuración ---
API_ENDPOINT = "https://httpbin.org/post"  # ¡¡CAMBIA ESTO por la URL real de tu API!!
TARGET_GROUP_NAME = "Nombre Exacto Del Grupo" # ¡¡CAMBIA ESTO por el nombre exacto de tu grupo!!
NODE_SCRIPT_PATH = os.path.join(os.path.dirname(__file__), 'bot.js') # Asume que bot.js está en la misma carpeta
# --------------------

def run_node_bot():
    # Verificar si Node.js está instalado (básico)
    try:
        subprocess.run(['node', '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print("Node.js encontrado.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: Node.js no parece estar instalado o no está en el PATH.")
        print("Por favor, instálalo desde https://nodejs.org/")
        sys.exit(1)

    # Verificar si el script bot.js existe
    if not os.path.exists(NODE_SCRIPT_PATH):
        print(f"Error: No se encuentra el script del bot en {NODE_SCRIPT_PATH}")
        sys.exit(1)

    print(f"Lanzando el bot de Node.js ({NODE_SCRIPT_PATH})...")
    print(f"API Endpoint: {API_ENDPOINT}")
    print(f"Grupo Objetivo: {TARGET_GROUP_NAME}")
    print("-" * 30)
    print("Espera a que aparezca el código QR y escánéalo con WhatsApp.")
    print("Presiona Ctrl+C en la terminal para detener el bot.")
    print("-" * 30)

    # Construir el comando para ejecutar el script de Node.js
    command = ['node', NODE_SCRIPT_PATH, API_ENDPOINT, TARGET_GROUP_NAME]

    try:
        # Ejecutar el script de Node.js como un subproceso
        # Usamos Popen para ver la salida en tiempo real (incluido el QR)
        process = subprocess.Popen(command, stdout=sys.stdout, stderr=sys.stderr)
        process.wait() # Esperar a que el proceso de Node.js termine

    except KeyboardInterrupt:
        print("\nInterrupción detectada. Intentando detener el bot de Node.js...")
        if 'process' in locals() and process.poll() is None:
             # Enviar señal SIGINT (equivalente a Ctrl+C) al proceso hijo si sigue vivo
             process.terminate() # o process.send_signal(signal.SIGINT) en Unix
             process.wait() # Esperar a que termine limpiamente si es posible
        print("Bot detenido.")
    except Exception as e:
        print(f"\nOcurrió un error al ejecutar el bot: {e}")
    finally:
        print("Script de Python finalizado.")


if __name__ == "__main__":
    # Validaciones básicas de configuración
    if "https://httpbin.org/post" in API_ENDPOINT or "CAMBIA ESTO" in API_ENDPOINT:
         print("ADVERTENCIA: Parece que no has cambiado la API_ENDPOINT de ejemplo.")
         print("El bot enviará datos a https://httpbin.org/post")
         input("Presiona Enter para continuar si estás seguro...")

    if "Nombre Exacto Del Grupo" in TARGET_GROUP_NAME or "CAMBIA ESTO" in TARGET_GROUP_NAME:
         print("ERROR: Debes especificar el TARGET_GROUP_NAME en run_bot.py")
         sys.exit(1)

    run_node_bot()

