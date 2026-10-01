#!/bin/bash
# ==============================================================================
# EviDump - Recolección de Evidencias Forenses para Linux
# ==============================================================================
# Version: 3.0
# Autor: MARH 

# Nota: no se usa "set -e". En una recolección forense un fallo aislado
# (un proceso que termina, un archivo ilegible...) no debe detener la
# adquisición completa; los errores relevantes se controlan explícitamente.

# Variables globales
VERSION="3.0"
LOG_FILE=""
STARTED_AT=$(date +%s)
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
EVIDENCE_DIR=""
CASE_NAME=""
AVAILABLE_SPACE=0
REQUIRED_SPACE=500  # En MB, estimación conservadora
PROGRESS_ACTIVE=0
FINISHED=0

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Banner de inicio
show_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo " ______     _ _____                        _      _       "
    echo "|  ____|   (_)  __ \                      | |    (_)      "
    echo "| |____   ___| |  | |_   _ _ __ ___  _ __ | |     _ _ __  "
    echo "|  __\ \ / / | |  | | | | | '_ \ _ \\| '_ \\| |    | | '_ \\ "
    echo "| |___\ V /| | |__| | |_| | | | | | | |_) | |____| | | | |"
    echo "|______\_/ |_|_____/ \__,_|_| |_| |_| .__/|______|_|_| |_|"
    echo "                                    | |                   "
    echo "                                    |_|                   "
    echo -e "${NC}"
    echo -e "${CYAN}${BOLD}Versión: ${VERSION} - Herramienta Forense para Linux - By: MARH${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════${NC}"
    echo ""
}

# Verificar si es root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}[ERROR] Este script requiere privilegios de superusuario${NC}"
        echo -e "${YELLOW}Por favor ejecute: sudo $0${NC}"
        exit 1
    fi
}

# Función para verificar si el comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para registrar en el log
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Si el log file está definido, escribir ahí
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
    
    # Los mensajes DEBUG solo se guardan en el archivo de log
    if [ "$level" != "DEBUG" ]; then
        # Si hay una barra de progreso a medias, cerrar su línea primero
        if [ "$PROGRESS_ACTIVE" -eq 1 ]; then
            echo ""
            PROGRESS_ACTIVE=0
        fi
        case "$level" in
            INFO)
                echo -e "${GREEN}[INFO]${NC} $message"
                ;;
            WARNING)
                echo -e "${YELLOW}[WARNING]${NC} $message"
                ;;
            ERROR)
                echo -e "${RED}[ERROR]${NC} $message"
                ;;
            DEBUG)
                echo -e "${MAGENTA}[DEBUG]${NC} $message"
                ;;
            SUCCESS)
                echo -e "${GREEN}[SUCCESS]${NC} $message"
                ;;
            *)
                echo -e "[LOG] $message"
                ;;
        esac
    fi
}

# Función para mostrar barra de progreso
show_progress() {
    local title="$1"
    local current="$2"
    local total="$3"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r${BLUE}%-20s${NC} [" "$title"
    printf "%${completed}s" | tr ' ' '#'
    printf "%${remaining}s" | tr ' ' ' '
    printf "] %3d%%" "$percentage"
    
    if [ "$current" -eq "$total" ]; then
        echo -e " ${GREEN}✓${NC}"
        PROGRESS_ACTIVE=0
    else
        PROGRESS_ACTIVE=1
    fi
}

# Solicitar el nombre del caso (opcional)
ask_case_name() {
    while true; do
        if ! read -r -p "Nombre del caso (Enter para omitir): " CASE_NAME; then
            echo ""
            log "ERROR" "No se pudo leer la entrada del usuario"
            exit 1
        fi
        
        # Evitar que el nombre del caso altere la ruta de destino
        if [ -z "$CASE_NAME" ] || [[ "$CASE_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
            return 0
        fi
        log "ERROR" "Nombre de caso no válido. Use solo letras, números, punto, guion y guion bajo."
    done
}

# Función para verificar herramientas necesarias
check_required_tools() {
    local tools=("tar" "date" "find" "grep" "awk" "sed" "sha256sum")
    local missing_tools=()
    
    log "INFO" "Verificando herramientas requeridas..."
    
    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "WARNING" "Herramientas faltantes: ${missing_tools[*]}"
        echo -e "${YELLOW}Se recomienda instalar las herramientas faltantes para un rendimiento óptimo.${NC}"
        sleep 2
    else
        log "SUCCESS" "Todas las herramientas requeridas están disponibles"
    fi
}

# Espacio libre en MB de la ruta indicada (-P evita que df parta la línea
# cuando el nombre del dispositivo es largo, p. ej. LVM)
get_free_space_mb() {
    df -Pm "$1" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Pide una ruta al usuario hasta que sea válida y tenga espacio suficiente
# (o el usuario acepte continuar). Deja el resultado en SELECTED_DIR.
ask_directory() {
    local prompt="$1"
    local dir space_confirm
    
    while true; do
        if ! read -r -p "$prompt" dir; then
            echo ""
            log "ERROR" "No se pudo leer la entrada del usuario"
            exit 1
        fi
        
        if [ -d "$dir" ] && [ -w "$dir" ]; then
            AVAILABLE_SPACE=$(get_free_space_mb "$dir")
            AVAILABLE_SPACE=${AVAILABLE_SPACE:-0}
            
            if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
                log "WARNING" "Espacio disponible en $dir: ${AVAILABLE_SPACE}MB (recomendado: ${REQUIRED_SPACE}MB)"
                read -r -p "¿Continuar de todos modos? (s/n): " space_confirm || space_confirm="n"
                if [[ "$space_confirm" =~ ^[Ss]$ ]]; then
                    SELECTED_DIR="$dir"
                    return 0
                fi
            else
                SELECTED_DIR="$dir"
                return 0
            fi
        else
            log "ERROR" "El directorio $dir no existe o no tiene permisos de escritura."
        fi
    done
}

# Función para comprobar y crear directorios
setup_directories() {
    local base_dir=""
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Solicitar al usuario la ubicación para guardar las evidencias
    echo -e "${CYAN}${BOLD}============================================${NC}"
    echo -e "${CYAN}${BOLD}||  ¿Dónde desea guardar las evidencias?  ||${NC}"
    echo -e "${CYAN}${BOLD}||                                        ||${NC}"
    echo -e "${CYAN}${BOLD}||  1. En un dispositivo USB              ||${NC}"
    echo -e "${CYAN}${BOLD}||  2. En un directorio local             ||${NC}"
    echo -e "${CYAN}${BOLD}||  3. Cancelar                           ||${NC}"
    echo -e "${CYAN}${BOLD}============================================${NC}"
    
    local choice
    while [ -z "$base_dir" ]; do
        if ! read -r -p "Ingrese el número de opción (1-3): " choice; then
            echo ""
            log "ERROR" "No se pudo leer la entrada del usuario"
            exit 1
        fi
        
        case "$choice" in
            1)
                # Mostrar dispositivos USB disponibles (TRAN = bus de conexión del disco)
                echo -e "\n${BOLD}Dispositivos USB detectados:${NC}"
                local usb_disks=()
                read -r -a usb_disks <<< "$(lsblk -dno NAME,TRAN 2>/dev/null | awk '$2=="usb" {printf "/dev/%s ", $1}')"
                if [ ${#usb_disks[@]} -gt 0 ]; then
                    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "${usb_disks[@]}" 2>/dev/null
                else
                    echo "  (no se detectaron dispositivos USB; puede indicar el punto de montaje igualmente)"
                fi
                
                ask_directory "Ingrese el punto de montaje del USB (ej. /media/usb): "
                base_dir="$SELECTED_DIR"
                ;;
            2)
                log "WARNING" "Guardar las evidencias en el propio sistema investigado modifica el disco analizado"
                ask_directory "Ingrese la ruta del directorio local: "
                base_dir="$SELECTED_DIR"
                ;;
            3)
                log "INFO" "Operación cancelada por el usuario"
                exit 0
                ;;
            *)
                log "ERROR" "Opción no válida. Por favor, seleccione 1, 2 o 3."
                ;;
        esac
    done
    
    # Generar nombre del directorio de evidencias (sin barra doble si base_dir es "/")
    base_dir="${base_dir%/}"
    if [ -n "$CASE_NAME" ]; then
        EVIDENCE_DIR="${base_dir}/EviDump_${CASE_NAME}_${timestamp}"
    else
        EVIDENCE_DIR="${base_dir}/EviDump_${timestamp}"
    fi
    
    # Crear directorios
    if ! mkdir -p "$EVIDENCE_DIR"/{logs,sistema,usuarios,red,archivos,memoria,cronologia,servicios,aplicaciones,dispositivos}; then
        log "ERROR" "No se pudo crear el directorio de evidencias: $EVIDENCE_DIR"
        exit 1
    fi
    
    # Configurar archivo de registro
    LOG_FILE="${EVIDENCE_DIR}/evidump.log"
    if ! touch "$LOG_FILE"; then
        log "ERROR" "No se pudo crear el archivo de registro: $LOG_FILE"
        exit 1
    fi
    
    log "SUCCESS" "Directorio de evidencias creado: $EVIDENCE_DIR"
}

# Función para ejecutar comandos y guardar resultados
run_and_save() {
    local cmd="$1"
    local outfile="$2"
    local description="$3"
    local timeout_value="${4:-60}"  # Valor por defecto: 60 segundos
    
    # Crear directorio padre si no existe
    mkdir -p "$(dirname "$outfile")"
    
    log "DEBUG" "Ejecutando: ${cmd}"
    
    # Cabecera del archivo
    {
        echo "===================================================="
        echo "COMANDO: ${cmd}"
        echo "DESCRIPCIÓN: ${description}"
        echo "FECHA DE EJECUCIÓN: $(date)"
        echo "===================================================="
    } > "${outfile}"
    
    # Ejecutar comando con timeout para evitar bloqueos
    if command_exists "timeout"; then
        # Usar timeout para limitar la duración del comando
        timeout "$timeout_value" bash -c "$cmd" >> "${outfile}" 2>&1 || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "ADVERTENCIA: El comando excedió el tiempo límite de ${timeout_value}s y fue terminado." >> "${outfile}"
                log "WARNING" "El comando '$cmd' excedió el tiempo límite y fue terminado"
            else
                echo "ERROR: El comando falló con código de salida $exit_code" >> "${outfile}"
                log "WARNING" "El comando '$cmd' falló con código $exit_code"
            fi
        }
    else
        # Si no está disponible timeout, ejecutar normalmente
        eval "$cmd" >> "${outfile}" 2>&1 || {
            local exit_code=$?
            echo "ERROR: El comando falló con código de salida $exit_code" >> "${outfile}"
            log "WARNING" "El comando '$cmd' falló con código $exit_code"
        }
    fi
    
    # Agregar un separador al final
    echo -e "\n\n" >> "${outfile}"
}

# Nombre de la distribución (PRETTY_NAME de /etc/os-release)
get_os_name() {
    local name
    # shellcheck source=/dev/null
    name=$( . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" )
    echo "${name:-desconocido}"
}

# Lista "usuario:directorio_home" de todas las cuentas de /etc/passwd cuyo
# directorio home existe (incluye root y homes fuera de /home)
get_user_homes() {
    local seen=" "
    local user home
    while IFS=: read -r user _ _ _ _ home _; do
        [ -n "$home" ] && [ "$home" != "/" ] && [ -d "$home" ] || continue
        # Evitar procesar dos veces el mismo directorio
        case "$seen" in *" $home "*) continue ;; esac
        seen="${seen}${home} "
        echo "${user}:${home}"
    done < /etc/passwd
}

# Función para generar un informe resumen
generate_summary() {
    local summary_file="${EVIDENCE_DIR}/resumen_evidencias.txt"
    local end_time duration hostname os_info kernel
    end_time=$(date +%s)
    duration=$((end_time - STARTED_AT))
    hostname=$(hostname 2>/dev/null || echo "desconocido")
    os_info=$(get_os_name)
    kernel=$(uname -r 2>/dev/null || echo "desconocido")
    
    # Generar resumen
    {
        echo "==========================================================="
        echo "          RESUMEN DE LA RECOLECCIÓN DE EVIDENCIAS          "
        echo "==========================================================="
        echo ""
        echo "FECHA Y HORA DE INICIO: $(date -d "@$STARTED_AT" "+%Y-%m-%d %H:%M:%S %Z")"
        echo "FECHA Y HORA DE FIN: $(date -d "@$end_time" "+%Y-%m-%d %H:%M:%S %Z")"
        echo "DURACIÓN: $((duration / 60)) minutos y $((duration % 60)) segundos"
        echo ""
        echo "INFORMACIÓN DEL SISTEMA:"
        echo "  - Hostname: $hostname"
        echo "  - Sistema Operativo: $os_info"
        echo "  - Kernel: $kernel"
        echo ""
        echo "DIRECTORIO DE EVIDENCIAS: $EVIDENCE_DIR"
        echo ""
        echo "ESTRUCTURA DE DIRECTORIOS:"
        (cd "$EVIDENCE_DIR" && find . -type d | sort | sed 's/^/  /')
        echo ""
        echo "ARCHIVOS GENERADOS:"
        find "$EVIDENCE_DIR" -type f -name "*.txt" | wc -l | xargs echo "  - Archivos de texto:"
        find "$EVIDENCE_DIR" -type f -name "*.tar.gz" | wc -l | xargs echo "  - Archivos comprimidos:"
        find "$EVIDENCE_DIR" -type f \( -name "*.bin" -o -name "*.lime" \) | wc -l | xargs echo "  - Volcados de memoria:"
        echo ""
        echo "TAMAÑO TOTAL DE EVIDENCIAS: $(du -sh "$EVIDENCE_DIR" | cut -f1)"
        echo ""
        echo "HASH SHA256 DE EVIDENCIAS CLAVE:"
        find "$EVIDENCE_DIR" -type f \( -name "*.tar.gz" -o -name "*.bin" -o -name "*.lime" \) -print0 |
            while IFS= read -r -d '' file; do
                echo "  - ${file#"$EVIDENCE_DIR"/}: $(sha256sum "$file" | cut -d' ' -f1)"
            done
        echo ""
        echo "==========================================================="
        echo "                 FIN DEL INFORME DE EVIDENCIAS             "
        echo "==========================================================="
    } > "$summary_file"
    
    # Calcular hash del resumen
    if command_exists "sha256sum"; then
        (cd "$EVIDENCE_DIR" && sha256sum resumen_evidencias.txt > resumen_evidencias.txt.sha256)
    fi
    
    log "SUCCESS" "Resumen de evidencias generado: $summary_file"
}

# Generar un archivo de identificación del sistema
generate_system_id() {
    local id_file="${EVIDENCE_DIR}/identificacion_sistema.txt"
    
    {
        echo "==========================================================="
        echo "          IDENTIFICACIÓN DEL SISTEMA                       "
        echo "==========================================================="
        echo ""
        echo "FECHA Y HORA: $(date)"
        echo "HOSTNAME: $(hostname 2>/dev/null || echo "N/A")"
        echo "USUARIO EJECUTANDO SCRIPT: $(whoami) (sesión original: ${SUDO_USER:-$(logname 2>/dev/null || echo "N/A")})"
        echo ""
        echo "INFORMACIÓN DEL SISTEMA:"
        echo "  - Kernel: $(uname -a 2>/dev/null || echo "N/A")"
        
        if [ -f "/etc/os-release" ]; then
            echo "  - Distribución: $(get_os_name)"
        fi
        
        echo "  - Arquitectura: $(uname -m 2>/dev/null || echo "N/A")"
        echo ""
        echo "INFORMACIÓN DE HARDWARE:"
        if command_exists "dmidecode"; then
            echo "  - Fabricante: $(dmidecode -s system-manufacturer 2>/dev/null || echo "N/A")"
            echo "  - Modelo: $(dmidecode -s system-product-name 2>/dev/null || echo "N/A")"
            echo "  - Serial: $(dmidecode -s system-serial-number 2>/dev/null || echo "N/A")"
        else
            echo "  - [dmidecode no disponible]"
        fi
        echo ""
        echo "INFORMACIÓN DE RED:"
        echo "  - Interfaces:"
        if command_exists "ip"; then
            ip -o link show | awk '{print "    - " $2 " " $3}' | sed 's/://'
        else
            echo "    [No se pudo obtener información de interfaces]"
        fi
        echo ""
        echo "HASH SHA256 INICIAL DEL DIRECTORIO /bin:"
        if command_exists "find" && command_exists "sha256sum"; then
            # "/bin/" con barra final: en las distros actuales /bin es un enlace a usr/bin
            find /bin/ -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1
        else
            echo "  [No se pudo calcular el hash]"
        fi
        echo ""
        echo "==========================================================="
    } > "$id_file"
    
    log "SUCCESS" "Archivo de identificación del sistema generado"
}

# Recolectar información del sistema
collect_system_info() {
    log "INFO" "Recolectando información del sistema..."
    local total_cmds=15
    local current_cmd=0
    
    # Información básica del sistema
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "date" "${EVIDENCE_DIR}/sistema/fecha.txt" "Fecha y hora del sistema"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "hostname" "${EVIDENCE_DIR}/sistema/hostname.txt" "Nombre del host"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "uname -a" "${EVIDENCE_DIR}/sistema/uname.txt" "Información del kernel"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/*-release" "${EVIDENCE_DIR}/sistema/distribucion.txt" "Información de la distribución"
    
    # Hardware y recursos
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "lscpu" "${EVIDENCE_DIR}/sistema/cpu_info.txt" "Información de CPU"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "free -m" "${EVIDENCE_DIR}/sistema/memoria.txt" "Información de memoria"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "df -h" "${EVIDENCE_DIR}/sistema/espacio_disco.txt" "Uso del espacio en disco"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID" "${EVIDENCE_DIR}/sistema/dispositivos_bloque.txt" "Dispositivos de bloques"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "mount" "${EVIDENCE_DIR}/sistema/puntos_montaje.txt" "Puntos de montaje"
    
    # Información de sistema de archivos
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "fdisk -l" "${EVIDENCE_DIR}/sistema/particiones_fdisk.txt" "Tablas de particiones (fdisk)"
    
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    if command_exists "parted"; then
        run_and_save "parted -l" "${EVIDENCE_DIR}/sistema/particiones_parted.txt" "Tablas de particiones (parted)"
    fi
    
    # Módulos del kernel
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "lsmod" "${EVIDENCE_DIR}/sistema/modulos_kernel.txt" "Módulos del kernel cargados"
    
    # Parámetros del kernel
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "cat /proc/cmdline" "${EVIDENCE_DIR}/sistema/cmdline_kernel.txt" "Parámetros del kernel"
    
    # Tiempo de actividad
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "uptime" "${EVIDENCE_DIR}/sistema/uptime.txt" "Tiempo de actividad"
    
    # Variables de entorno
    show_progress "Info Sistema" $((++current_cmd)) $total_cmds
    run_and_save "env; echo; echo '--- Entorno de PID 1 (init) ---'; tr '\\0' '\\n' < /proc/1/environ" \
                "${EVIDENCE_DIR}/sistema/variables_entorno.txt" "Variables de entorno (del script y de PID 1)"
    
    log "SUCCESS" "Información del sistema recolectada"
}

# Recolectar información sobre procesos
collect_process_info() {
    log "INFO" "Recolectando información de procesos..."
    local total_cmds=8
    local current_cmd=0
    
    # Procesos en ejecución
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    run_and_save "ps aux" "${EVIDENCE_DIR}/sistema/procesos.txt" "Procesos en ejecución"
    
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    run_and_save "ps auxf" "${EVIDENCE_DIR}/sistema/arbol_procesos.txt" "Árbol de procesos"
    
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    run_and_save "ps -eo pid,ppid,user,cmd --sort=user" "${EVIDENCE_DIR}/sistema/procesos_por_usuario.txt" "Procesos ordenados por usuario"
    
    # Estadísticas de procesos
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    run_and_save "top -b -n 1" "${EVIDENCE_DIR}/sistema/top.txt" "Estadísticas de procesos (top)"
    
    # Archivos abiertos
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    if command_exists "lsof"; then
        run_and_save "lsof" "${EVIDENCE_DIR}/sistema/archivos_abiertos.txt" "Archivos abiertos por procesos" 120
    fi
    
    # Tareas cron
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    if compgen -G "/etc/cron*" > /dev/null; then
        run_and_save "ls -la /etc/cron*" "${EVIDENCE_DIR}/cronologia/cron_directorios.txt" "Directorios de cron"
    fi
    
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    if compgen -G "/etc/cron*" > /dev/null; then
        run_and_save "find /etc/cron* -type f -print -exec cat {} \;" "${EVIDENCE_DIR}/cronologia/cron_trabajos.txt" "Trabajos de cron"
    fi
    
    # Crontabs de todos los usuarios (incluido root), directamente desde el spool:
    # Debian/Ubuntu usan /var/spool/cron/crontabs, RHEL/Fedora /var/spool/cron
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    local spool_dir
    for spool_dir in /var/spool/cron/crontabs /var/spool/cron; do
        if [ -d "$spool_dir" ]; then
            run_and_save "ls -la $(printf '%q' "$spool_dir")" "${EVIDENCE_DIR}/cronologia/spool_listado.txt" "Listado del spool de cron"
            mkdir -p "${EVIDENCE_DIR}/cronologia/spool"
            find "$spool_dir" -maxdepth 1 -type f -exec cp -p {} "${EVIDENCE_DIR}/cronologia/spool/" \; 2>/dev/null
            break
        fi
    done
    
    # Tareas programadas con at
    if command_exists "atq"; then
        run_and_save "atq" "${EVIDENCE_DIR}/cronologia/at_trabajos.txt" "Trabajos programados con at"
    fi
    
    log "SUCCESS" "Información de procesos recolectada"
}

# Recolectar información de usuarios
collect_user_info() {
    log "INFO" "Recolectando información de usuarios..."
    local total_cmds=8
    local current_cmd=0
    
    # Información de cuentas
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/passwd" "${EVIDENCE_DIR}/usuarios/passwd.txt" "Archivo passwd"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/group" "${EVIDENCE_DIR}/usuarios/group.txt" "Archivo group"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/shadow" "${EVIDENCE_DIR}/usuarios/shadow.txt" "Archivo shadow"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/sudoers" "${EVIDENCE_DIR}/usuarios/sudoers.txt" "Archivo sudoers"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    if [ -d /etc/sudoers.d ]; then
        run_and_save "find /etc/sudoers.d -type f -print -exec cat {} \;" "${EVIDENCE_DIR}/usuarios/sudoers_adicional.txt" "Configuración adicional de sudoers"
    fi
    
    # Historial de login
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "last" "${EVIDENCE_DIR}/usuarios/last.txt" "Últimos logins"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "lastlog" "${EVIDENCE_DIR}/usuarios/lastlog.txt" "Registro de último login por usuario"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "w" "${EVIDENCE_DIR}/usuarios/usuarios_activos.txt" "Usuarios actualmente activos"
    
    # Copiar .bash_history de usuarios
    log "INFO" "Copiando historial de comandos de usuarios..."
    
    # Se recorren todas las cuentas de /etc/passwd (incluido root y homes fuera de /home)
    local username user_home history_file
    while IFS=: read -r username user_home; do
        # Historiales de shell
        for history_file in "${user_home}/.bash_history" "${user_home}/.zsh_history" "${user_home}/.history" "${user_home}/.sh_history"; do
            if [ -f "$history_file" ]; then
                cp -p "$history_file" "${EVIDENCE_DIR}/usuarios/$(basename "$history_file")_${username}.txt" 2>/dev/null ||
                    log "WARNING" "No se pudo copiar $history_file"
            fi
        done
        
        # Archivos SSH (claves, authorized_keys, known_hosts, config)
        if [ -d "${user_home}/.ssh" ]; then
            mkdir -p "${EVIDENCE_DIR}/usuarios/ssh_${username}"
            # "/." copia también los ocultos y no falla si la carpeta está vacía
            cp -a "${user_home}/.ssh/." "${EVIDENCE_DIR}/usuarios/ssh_${username}/" 2>/dev/null ||
                log "WARNING" "No se pudo copiar completamente ${user_home}/.ssh"
        fi
    done < <(get_user_homes)
    
    log "SUCCESS" "Información de usuarios recolectada"
}

# Recolectar información de servicios
collect_service_info() {
    log "INFO" "Recolectando información de servicios..."
    local total_cmds=6
    local current_cmd=0
    
    # Servicios systemd
    show_progress "Servicios" $((++current_cmd)) $total_cmds
    if command_exists "systemctl"; then
        run_and_save "systemctl list-units --type=service --all" "${EVIDENCE_DIR}/servicios/systemd_servicios.txt" "Servicios systemd"
    fi
    
    show_progress "Servicios" $((++current_cmd)) $total_cmds
    if command_exists "systemctl"; then
        run_and_save "systemctl list-unit-files" "${EVIDENCE_DIR}/servicios/systemd_unit_files.txt" "Archivos de unidad systemd"
    fi
    
    # Servicios init.d (sistemas antiguos)
    show_progress "Servicios" $((++current_cmd)) $total_cmds
    if [ -d /etc/init.d ]; then
        run_and_save "ls -la /etc/init.d/" "${EVIDENCE_DIR}/servicios/init_scripts.txt" "Scripts init.d"
    fi
    
    # Targets y niveles de ejecución
    show_progress "Servicios" $((++current_cmd)) $total_cmds
    if command_exists "systemctl"; then
        run_and_save "systemctl list-units --type=target" "${EVIDENCE_DIR}/servicios/systemd_targets.txt" "Targets systemd"
    fi
    
    # Servicios en inicio
    show_progress "Servicios" $((++current_cmd)) $total_cmds
    if command_exists "systemctl"; then
        run_and_save "systemctl list-unit-files --state=enabled" "${EVIDENCE_DIR}/servicios/servicios_habilitados.txt" "Servicios habilitados"
    fi
    
    # Servicios fallidos
    show_progress "Servicios" $((++current_cmd)) $total_cmds
    if command_exists "systemctl"; then
        run_and_save "systemctl --failed" "${EVIDENCE_DIR}/servicios/servicios_fallidos.txt" "Servicios fallidos"
    fi
    
    log "SUCCESS" "Información de servicios recolectada"
}

# Recolectar logs
collect_logs() {
    log "INFO" "Recolectando logs del sistema..."
    
    # Comprimir logs completos
    if command_exists "tar"; then
        # Código 1 de GNU tar = "algún archivo cambió durante la lectura", habitual
        # en logs activos: el archivo generado es válido, solo se avisa.
        local tar_rc=0
        tar -czf "${EVIDENCE_DIR}/logs/logs_completos.tar.gz" \
            --exclude="${EVIDENCE_DIR#/}" -C / var/log 2>/dev/null || tar_rc=$?
        if [ "$tar_rc" -eq 1 ]; then
            log "WARNING" "Algunos logs cambiaron mientras se comprimían (normal en un sistema en ejecución)"
        elif [ "$tar_rc" -gt 1 ]; then
            log "ERROR" "Error al comprimir los logs (código $tar_rc)"
        fi
    else
        cp -r /var/log/* "${EVIDENCE_DIR}/logs/" 2>/dev/null
    fi
    
    # Extraer logs específicos importantes
    for log_file in /var/log/auth.log /var/log/syslog /var/log/messages /var/log/secure; do
        if [ -f "$log_file" ]; then
            cp "$log_file" "${EVIDENCE_DIR}/logs/$(basename "$log_file")" 2>/dev/null
        fi
    done
    
    # Logs de aplicaciones críticas
    for app_dir in /var/log/apache2 /var/log/nginx /var/log/mysql /var/log/postgresql; do
        if [ -d "$app_dir" ]; then
            app_name=$(basename "$app_dir")
            mkdir -p "${EVIDENCE_DIR}/logs/${app_name}"
            find "$app_dir" -type f -name "*.log" -exec cp {} "${EVIDENCE_DIR}/logs/${app_name}/" \; 2>/dev/null
        fi
    done
    
    # Journalctl logs (systemd)
    if command_exists "journalctl"; then
        run_and_save "journalctl -b" "${EVIDENCE_DIR}/logs/journal_boot.txt" "Logs del arranque actual" 120
        run_and_save "journalctl --disk-usage" "${EVIDENCE_DIR}/logs/journal_disk_usage.txt" "Uso de disco de journal"
        
        # Logs de autenticación
        run_and_save "journalctl _COMM=sshd" "${EVIDENCE_DIR}/logs/journal_sshd.txt" "Logs de SSH" 60
        run_and_save "journalctl _COMM=sudo" "${EVIDENCE_DIR}/logs/journal_sudo.txt" "Logs de sudo" 60
    fi
    
    # Auditoría
    if command_exists "ausearch"; then
        run_and_save "ausearch -i" "${EVIDENCE_DIR}/logs/auditd_all.txt" "Logs de auditd" 120
        run_and_save "ausearch -i -m USER_LOGIN" "${EVIDENCE_DIR}/logs/auditd_login.txt" "Logs de login de auditd" 60
    fi
    
    log "SUCCESS" "Logs del sistema recolectados"
}

# Recolectar información de red
collect_network_info() {
    log "INFO" "Recolectando información de red..."
    local total_cmds=15
    local current_cmd=0
    
    # Interfaces y configuración
    show_progress "Red" $((++current_cmd)) $total_cmds
    run_and_save "ip addr" "${EVIDENCE_DIR}/red/ip_addr.txt" "Direcciones IP"
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    run_and_save "ip link" "${EVIDENCE_DIR}/red/ip_link.txt" "Interfaces de red"
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    if command_exists "ifconfig"; then
        run_and_save "ifconfig -a" "${EVIDENCE_DIR}/red/ifconfig.txt" "Configuración de interfaces (ifconfig)"
    fi
    
    # Tabla de enrutamiento
    show_progress "Red" $((++current_cmd)) $total_cmds
    run_and_save "ip route" "${EVIDENCE_DIR}/red/ip_route.txt" "Tabla de rutas IP"
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    if command_exists "route"; then
        run_and_save "route -n" "${EVIDENCE_DIR}/red/route.txt" "Tabla de rutas (route)"
    fi
    
    # Conexiones activas
    show_progress "Red" $((++current_cmd)) $total_cmds
    if command_exists "netstat"; then
        run_and_save "netstat -tulpn" "${EVIDENCE_DIR}/red/netstat_tulpn.txt" "Conexiones activas (netstat)"
        run_and_save "netstat -an" "${EVIDENCE_DIR}/red/netstat_an.txt" "Todas las conexiones (netstat)"
    else
        run_and_save "ss -tulpn" "${EVIDENCE_DIR}/red/ss_tulpn.txt" "Conexiones activas (ss)"
        run_and_save "ss -an" "${EVIDENCE_DIR}/red/ss_an.txt" "Todas las conexiones (ss)"
    fi
    
    # Estadísticas
    show_progress "Red" $((++current_cmd)) $total_cmds
    if command_exists "netstat"; then
        run_and_save "netstat -s" "${EVIDENCE_DIR}/red/netstat_stats.txt" "Estadísticas de protocolos"
    else
        run_and_save "ss -s" "${EVIDENCE_DIR}/red/ss_stats.txt" "Estadísticas de sockets"
    fi
    
    # ARP
    show_progress "Red" $((++current_cmd)) $total_cmds
    run_and_save "ip neigh" "${EVIDENCE_DIR}/red/ip_neigh.txt" "Tabla de vecinos IP"
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    if command_exists "arp"; then
        run_and_save "arp -an" "${EVIDENCE_DIR}/red/arp.txt" "Tabla ARP"
    fi
    
    # DNS
    show_progress "Red" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/hosts" "${EVIDENCE_DIR}/red/hosts.txt" "Archivo hosts"
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/resolv.conf" "${EVIDENCE_DIR}/red/resolv_conf.txt" "Configuración DNS"
    
    # Información de hosts permitidos/denegados
    show_progress "Red" $((++current_cmd)) $total_cmds
    if [ -f /etc/hosts.allow ]; then
        run_and_save "cat /etc/hosts.allow" "${EVIDENCE_DIR}/red/hosts_allow.txt" "Hosts permitidos"
    fi
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    if [ -f /etc/hosts.deny ]; then
        run_and_save "cat /etc/hosts.deny" "${EVIDENCE_DIR}/red/hosts_deny.txt" "Hosts denegados"
    fi
    
    # Configuración de firewall
    show_progress "Red" $((++current_cmd)) $total_cmds
    if command_exists "iptables"; then
        run_and_save "iptables -L -v -n" "${EVIDENCE_DIR}/red/iptables.txt" "Reglas de iptables"
    fi
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    if command_exists "ufw"; then
        run_and_save "ufw status verbose" "${EVIDENCE_DIR}/red/ufw_status.txt" "Estado de UFW"
    fi
    
    log "SUCCESS" "Información de red recolectada"
}

# Recolectar información de archivos sospechosos
collect_suspicious_files() {
    log "INFO" "Buscando archivos sospechosos..."
    
    # Excluir pseudo-sistemas de archivos, montajes de red y el propio directorio
    # de evidencias (si no, la evidencia se incluye a sí misma). "|| true": find
    # devuelve error por cualquier archivo ilegible o que desaparezca, y eso no
    # invalida el resultado.
    local prune
    prune="\\( -path /proc -o -path /sys -o -path /run -o -path /dev -o -path $(printf '%q' "$EVIDENCE_DIR")"
    prune+=" -o -fstype nfs -o -fstype nfs4 -o -fstype cifs -o -fstype smb3 -o -fstype fuse.sshfs \\) -prune -o"
    
    # Buscar archivos SUID/SGID
    run_and_save "find / $prune -type f \\( -perm -4000 -o -perm -2000 \\) -ls 2>/dev/null || true" \
                "${EVIDENCE_DIR}/archivos/suid_sgid.txt" "Archivos con SUID/SGID" 300
    
    # Buscar archivos recientemente modificados
    run_and_save "find / $prune -type f -mtime -7 -ls 2>/dev/null || true" \
                "${EVIDENCE_DIR}/archivos/modificados_ultimos_7dias.txt" "Archivos modificados en los últimos 7 días" 300
    
    # Buscar archivos ocultos
    run_and_save "find / $prune -type f -name '.*' -ls 2>/dev/null || true" \
                "${EVIDENCE_DIR}/archivos/archivos_ocultos.txt" "Archivos ocultos" 300
    
    # Buscar archivos en /tmp y /dev/shm (ubicaciones típicas de malware)
    run_and_save "find /tmp /var/tmp /dev/shm $prune -type f -ls 2>/dev/null || true" \
                "${EVIDENCE_DIR}/archivos/archivos_tmp.txt" "Archivos en /tmp, /var/tmp y /dev/shm" 60
    
    # Buscar archivos grandes
    run_and_save "find / $prune -type f -size +100M -ls 2>/dev/null || true" \
                "${EVIDENCE_DIR}/archivos/archivos_grandes.txt" "Archivos mayores a 100MB" 300
    
    # Archivos de inicio sospechosos
    if compgen -G "/etc/rc*.d" > /dev/null; then
        run_and_save "ls -la /etc/rc*.d/" "${EVIDENCE_DIR}/archivos/archivos_rc.txt" "Archivos rc.d"
    fi
    
    log "SUCCESS" "Búsqueda de archivos sospechosos completada"
}

# Recolectar información de dispositivos
collect_device_info() {
    log "INFO" "Recolectando información de dispositivos..."
    
    # Dispositivos PCI
    if command_exists "lspci"; then
        run_and_save "lspci -v" "${EVIDENCE_DIR}/dispositivos/lspci.txt" "Dispositivos PCI"
    fi
    
    # Dispositivos USB
    if command_exists "lsusb"; then
        run_and_save "lsusb -v" "${EVIDENCE_DIR}/dispositivos/lsusb.txt" "Dispositivos USB"
    fi
    
    # Dispositivos SCSI/SATA
    if [ -f /proc/scsi/scsi ]; then
        run_and_save "cat /proc/scsi/scsi" "${EVIDENCE_DIR}/dispositivos/scsi.txt" "Dispositivos SCSI"
    fi
    
    # DMI/SMBIOS
    if command_exists "dmidecode"; then
        run_and_save "dmidecode" "${EVIDENCE_DIR}/dispositivos/dmidecode.txt" "Información DMI/SMBIOS"
    fi
    
    log "SUCCESS" "Información de dispositivos recolectada"
}

# Recolectar información de aplicaciones
collect_app_info() {
    log "INFO" "Recolectando información de aplicaciones..."
    
    # Paquetes instalados
    if command_exists "dpkg"; then
        run_and_save "dpkg -l" "${EVIDENCE_DIR}/aplicaciones/dpkg_paquetes.txt" "Paquetes instalados (dpkg)"
    elif command_exists "rpm"; then
        run_and_save "rpm -qa" "${EVIDENCE_DIR}/aplicaciones/rpm_paquetes.txt" "Paquetes instalados (rpm)"
    fi
    
    # Repositorios
    if [ -d "/etc/apt" ]; then
        run_and_save "cat /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null" "${EVIDENCE_DIR}/aplicaciones/apt_sources.txt" "Repositorios APT"
    elif [ -d "/etc/yum.repos.d" ]; then
        run_and_save "cat /etc/yum.repos.d/* 2>/dev/null" "${EVIDENCE_DIR}/aplicaciones/yum_repos.txt" "Repositorios YUM"
    fi
    
    # Binarios con capacidades
    if command_exists "getcap"; then
        run_and_save "getcap -r / 2>/dev/null" "${EVIDENCE_DIR}/aplicaciones/capabilities.txt" "Binarios con capacidades"
    fi
    
    # Configuración de aplicaciones sensibles
    for app_dir in /etc/ssh /etc/apache2 /etc/nginx /etc/mysql /etc/postgresql; do
        if [ -d "$app_dir" ]; then
            app_name=$(basename "$app_dir")
            mkdir -p "${EVIDENCE_DIR}/aplicaciones/${app_name}"
            find "$app_dir" -type f -name "*.conf" -exec cp {} "${EVIDENCE_DIR}/aplicaciones/${app_name}/" \; 2>/dev/null
        fi
    done
    
    log "SUCCESS" "Información de aplicaciones recolectada"
}

# Captura de memoria RAM (AVML, LiME o /dev/fmem si están disponibles)
collect_memory_image() {
    log "INFO" "Evaluando captura de memoria RAM..."
    
    local mem_dir="${EVIDENCE_DIR}/memoria"
    local mem_total_mb free_mb method="" lime_module="" candidate
    
    run_and_save "cat /proc/meminfo" "${mem_dir}/meminfo.txt" "Información de memoria"
    
    # Buscar una herramienta de captura. LiME y fmem son módulos del kernel, no
    # comandos: el módulo de LiME se busca junto al script o entre los módulos
    # instalados del kernel en ejecución.
    if command_exists "avml"; then
        method="avml"
    else
        for candidate in "$SCRIPT_PATH"/lime*.ko; do
            if [ -f "$candidate" ]; then
                lime_module="$candidate"
                break
            fi
        done
        if [ -z "$lime_module" ] && command_exists "modinfo"; then
            lime_module=$(modinfo -n lime 2>/dev/null)
        fi
        
        if [ -n "$lime_module" ] && command_exists "insmod"; then
            method="lime"
        elif [ -c /dev/fmem ]; then
            method="fmem"
        fi
    fi
    
    if [ -z "$method" ]; then
        log "INFO" "No se encontraron herramientas de captura de memoria (avml, módulo LiME o /dev/fmem)"
    else
        # Se necesita al menos el tamaño de la RAM más un 10% de margen
        mem_total_mb=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo 2>/dev/null)
        mem_total_mb=${mem_total_mb:-0}
        free_mb=$(get_free_space_mb "$EVIDENCE_DIR")
        free_mb=${free_mb:-0}
        
        if [ "$free_mb" -le $((mem_total_mb + mem_total_mb / 10)) ]; then
            log "WARNING" "Espacio insuficiente para la captura de RAM: ${free_mb}MB libres, RAM de ${mem_total_mb}MB"
        else
            log "INFO" "Capturando memoria RAM con ${method} (${mem_total_mb}MB), puede tardar varios minutos..."
            # Timeout 0 = sin límite de tiempo: el volcado no debe cortarse a medias
            case "$method" in
                avml)
                    run_and_save "avml $(printf '%q' "${mem_dir}/ram_dump.lime")" \
                                "${mem_dir}/avml_output.txt" "Captura de memoria con AVML" 0
                    ;;
                lime)
                    run_and_save "insmod $(printf '%q' "$lime_module") $(printf '%q' "path=${mem_dir}/ram_dump.lime format=lime")" \
                                "${mem_dir}/lime_output.txt" "Captura de memoria con LiME ($lime_module)" 0
                    rmmod lime 2>/dev/null
                    ;;
                fmem)
                    run_and_save "dd if=/dev/fmem of=$(printf '%q' "${mem_dir}/ram_dump.bin") bs=1M count=${mem_total_mb}" \
                                "${mem_dir}/fmem_output.txt" "Captura de memoria con fmem" 0
                    ;;
            esac
        fi
    fi
    
    # Capturar información de /proc para análisis similar a volatility
    log "INFO" "Capturando información de /proc para análisis de memoria..."
    
    # Directorio temporal para estructura /proc
    local proc_temp="${mem_dir}/proc_info"
    mkdir -p "$proc_temp"
    
    # Guardar mapas de memoria de procesos. Un proceso puede terminar mientras
    # se recorre la lista: en ese caso cp falla y simplemente se continúa.
    local pid pid_num proc_file
    for pid in /proc/[0-9]*; do
        if [ -d "$pid" ]; then
            pid_num=${pid#/proc/}
            mkdir -p "${proc_temp}/${pid_num}"
            for proc_file in maps status cmdline environ; do
                cp "${pid}/${proc_file}" "${proc_temp}/${pid_num}/" 2>/dev/null
            done
            # Ruta del ejecutable (permite detectar binarios borrados en uso)
            readlink "${pid}/exe" > "${proc_temp}/${pid_num}/exe_link" 2>/dev/null
        fi
    done
    
    # Comprimir para ahorrar espacio
    if command_exists "tar"; then
        if tar -czf "${mem_dir}/proc_info.tar.gz" -C "$mem_dir" proc_info 2>/dev/null; then
            rm -rf "$proc_temp"
        else
            log "WARNING" "No se pudo comprimir ${proc_temp}; se conserva sin comprimir"
        fi
    fi
    
    log "SUCCESS" "Captura de información de memoria completada"
}

# Función de limpieza y finalización
# $1 = "interrumpida" si se llama desde la captura de señales
cleanup_and_finish() {
    local status="${1:-completa}"
    
    # Calcular hashes de todos los archivos recolectados. Rutas relativas para
    # poder verificarlos en otro equipo:  cd <dir> && sha256sum -c hashes_sha256.txt
    # Se excluyen el propio archivo de hashes y el log (que aún se modifica);
    # ambos se cubren al final en hashes_cierre.sha256.
    log "INFO" "Calculando hashes de archivos recolectados..."
    
    local hash_file="${EVIDENCE_DIR}/hashes_sha256.txt"
    local hash_tmp="${EVIDENCE_DIR}/.hashes_sha256.tmp"
    
    if command_exists "sha256sum"; then
        if (cd "$EVIDENCE_DIR" && find . -type f \
                ! -name hashes_sha256.txt ! -name .hashes_sha256.tmp \
                ! -name evidump.log ! -name hashes_cierre.sha256 -print0 |
                sort -z | xargs -0 -r sha256sum) > "$hash_tmp" &&
           mv "$hash_tmp" "$hash_file"; then
            log "SUCCESS" "Hashes SHA256 calculados"
        else
            rm -f "$hash_tmp"
            log "WARNING" "No se pudieron calcular todos los hashes SHA256"
        fi
    else
        log "WARNING" "No se pudo calcular hashes SHA256 (sha256sum no disponible)"
    fi
    
    # Tiempo total
    local end_time duration minutes seconds
    end_time=$(date +%s)
    duration=$((end_time - STARTED_AT))
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    
    log "SUCCESS" "Recolección de evidencias ${status} en $minutes minutos y $seconds segundos"
    log "SUCCESS" "Evidencias guardadas en: $EVIDENCE_DIR"
    
    # Solo lectura (u+rX mantiene el acceso a los directorios). En FAT32/exFAT
    # no hay permisos Unix y chmod falla: se avisa y se continúa.
    if ! chmod -R a-w,u+rX "$EVIDENCE_DIR" 2>/dev/null; then
        log "WARNING" "No se pudieron aplicar permisos de solo lectura (¿sistema de archivos FAT/exFAT?)"
    fi
    
    # Cerrar el log y sellar el log y el archivo de hashes
    LOG_FILE=""
    if command_exists "sha256sum"; then
        (cd "$EVIDENCE_DIR" && sha256sum evidump.log hashes_sha256.txt > hashes_cierre.sha256 2>/dev/null)
        chmod a-w "${EVIDENCE_DIR}/hashes_cierre.sha256" 2>/dev/null
    fi
    FINISHED=1
    
    # Mensaje final
    echo ""
    if [ "$status" = "interrumpida" ]; then
        echo -e "${YELLOW}${BOLD}=======================================================${NC}"
        echo -e "${YELLOW}${BOLD}      RECOLECCIÓN INTERRUMPIDA (EVIDENCIAS PARCIALES)  ${NC}"
        echo -e "${YELLOW}${BOLD}=======================================================${NC}"
    else
        echo -e "${GREEN}${BOLD}=======================================================${NC}"
        echo -e "${GREEN}${BOLD}           RECOLECCIÓN FINALIZADA CON ÉXITO           ${NC}"
        echo -e "${GREEN}${BOLD}=======================================================${NC}"
    fi
    echo ""
    echo -e "${BOLD}Tiempo Total:${NC} $minutes minutos y $seconds segundos"
    echo -e "${BOLD}Directorio de Evidencias:${NC} $EVIDENCE_DIR"
    echo ""
    echo -e "${YELLOW}NOTA:${NC} Asegúrese de mantener seguro el directorio de evidencias"
    echo -e "      para preservar la integridad de la información forense."
    echo -e "      Verificación: cd \"$EVIDENCE_DIR\" && sha256sum -c hashes_sha256.txt"
    echo ""
}

# Si el usuario pulsa Ctrl+C o el proceso recibe SIGTERM, cerrar ordenadamente:
# se generan el resumen y los hashes de lo recolectado hasta ese momento.
on_interrupt() {
    trap - INT TERM
    echo ""
    log "WARNING" "Recolección interrumpida; generando resumen y hashes de lo recolectado..."
    if [ -n "$EVIDENCE_DIR" ] && [ -d "$EVIDENCE_DIR" ] && [ "$FINISHED" -eq 0 ]; then
        generate_summary
        cleanup_and_finish "interrumpida"
    fi
    exit 130
}

# Función principal
main() {
    # El script no admite parámetros: todo se solicita de forma interactiva
    if [ $# -gt 0 ]; then
        echo -e "${RED}Este script no admite parámetros.${NC} Uso: sudo $0"
        exit 1
    fi
    
    # Verificar privilegios
    check_root
    
    # Mostrar banner
    show_banner
    
    # Verificar herramientas necesarias
    check_required_tools
    
    # Datos del caso y ubicación de las evidencias
    ask_case_name
    setup_directories
    trap on_interrupt INT TERM
    
    # Generar identificación del sistema
    generate_system_id
    
    # Recolectar información en orden lógico
    collect_system_info
    collect_process_info
    collect_user_info
    collect_service_info
    collect_network_info
    collect_logs
    collect_suspicious_files
    collect_device_info
    collect_app_info
    collect_memory_image
    
    # Generar resumen
    generate_summary
    
    # Limpieza y finalización
    cleanup_and_finish
}

# Ejecutar función principal con todos los argumentos
main "$@"
