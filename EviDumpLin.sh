#!/bin/bash
# ==============================================================================
# EviDump - Recolección de Evidencias Forenses para Linux
# ==============================================================================
# Version: 2.0
# Autor: MARH 

set -e

# Variables globales
VERSION="2.0"
LOG_FILE=""
STARTED_AT=$(date +%s)
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
EVIDENCE_DIR=""
CASE_NAME=""
VERBOSE=0
AVAILABLE_SPACE=0
REQUIRED_SPACE=500  # En MB, estimación conservadora

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

# Función para mostrar ayuda
show_help() {
    echo -e "${BOLD}USO:${NC} sudo $0 [opciones]"
    echo ""
    echo "Opciones:"
    echo "  -h, --help          Muestra esta ayuda"
    echo "  -v, --verbose       Modo verboso"
    echo "  -c, --case NAME     Definir nombre del caso"
    echo "  -o, --output DIR    Directorio de salida específico"
    echo ""
    echo "Ejemplos:"
    echo "  sudo $0 -c caso_incidente_123 -o /media/usb"
    echo "  sudo $0 --verbose"
    exit 0
}

# Función para registrar en el log
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Si el log file está definido, escribir ahí
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
    
    # En modo verbose, mostrar todos los mensajes
    if [ $VERBOSE -eq 1 ] || [ "$level" != "DEBUG" ]; then
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
    fi
}

# Función para parsear argumentos
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -c|--case)
                CASE_NAME="$2"
                shift 2
                ;;
            -o|--output)
                USER_OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}Opción desconocida: $1${NC}"
                show_help
                ;;
        esac
    done
}

# Función para verificar herramientas necesarias
check_required_tools() {
    local tools=("tar" "dd" "date" "find" "grep" "awk" "sed")
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

# Función para comprobar y crear directorios
setup_directories() {
    local base_dir=""
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [ -n "$USER_OUTPUT_DIR" ]; then
        if [ -d "$USER_OUTPUT_DIR" ] && [ -w "$USER_OUTPUT_DIR" ]; then
            base_dir="$USER_OUTPUT_DIR"
        else
            log "ERROR" "El directorio especificado no existe o no se puede escribir: $USER_OUTPUT_DIR"
            exit 1
        fi
    else
        # Solicitar al usuario la ubicación para guardar las evidencias
        echo -e "${CYAN}${BOLD}============================================${NC}"
        echo -e "${CYAN}${BOLD}||  ¿Dónde desea guardar las evidencias?  ||${NC}"
        echo -e "${CYAN}${BOLD}||                                        ||${NC}"
        echo -e "${CYAN}${BOLD}||  1. En un dispositivo USB              ||${NC}"
        echo -e "${CYAN}${BOLD}||  2. En un directorio local             ||${NC}"
        echo -e "${CYAN}${BOLD}||  3. Cancelar                           ||${NC}"
        echo -e "${CYAN}${BOLD}============================================${NC}"
        
        local valid_choice=0
        while [ $valid_choice -eq 0 ]; do
            read -p "Ingrese el número de opción (1-3): " choice
            
            case "$choice" in
                1)
                    # Mostrar dispositivos USB disponibles
                    echo -e "\n${BOLD}Dispositivos USB detectados:${NC}"
                    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "sd[a-z]|usb"
                    
                    # Solicitar punto de montaje
                    local valid_mount=0
                    while [ $valid_mount -eq 0 ]; do
                        read -p "Ingrese el punto de montaje del USB (ej. /media/usb): " USB_MOUNT
                        
                        if [ -d "$USB_MOUNT" ] && [ -w "$USB_MOUNT" ]; then
                            # Verificar espacio disponible
                            AVAILABLE_SPACE=$(df -m "$USB_MOUNT" | awk 'NR==2 {print $4}')
                            
                            if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
                                log "WARNING" "Espacio disponible en $USB_MOUNT: ${AVAILABLE_SPACE}MB (recomendado: ${REQUIRED_SPACE}MB)"
                                read -p "¿Continuar de todos modos? (s/n): " space_confirm
                                
                                if [[ "$space_confirm" =~ ^[Ss]$ ]]; then
                                    base_dir="$USB_MOUNT"
                                    valid_mount=1
                                    valid_choice=1
                                fi
                            else
                                base_dir="$USB_MOUNT"
                                valid_mount=1
                                valid_choice=1
                            fi
                        else
                            log "ERROR" "El punto de montaje $USB_MOUNT no existe o no tiene permisos de escritura."
                        fi
                    done
                    ;;
                2)
                    # Directorio local
                    local valid_dir=0
                    while [ $valid_dir -eq 0 ]; do
                        read -p "Ingrese la ruta del directorio local (ej. /tmp): " LOCAL_DIR
                        
                        if [ -d "$LOCAL_DIR" ] && [ -w "$LOCAL_DIR" ]; then
                            # Verificar espacio disponible
                            AVAILABLE_SPACE=$(df -m "$LOCAL_DIR" | awk 'NR==2 {print $4}')
                            
                            if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
                                log "WARNING" "Espacio disponible en $LOCAL_DIR: ${AVAILABLE_SPACE}MB (recomendado: ${REQUIRED_SPACE}MB)"
                                read -p "¿Continuar de todos modos? (s/n): " space_confirm
                                
                                if [[ "$space_confirm" =~ ^[Ss]$ ]]; then
                                    base_dir="$LOCAL_DIR"
                                    valid_dir=1
                                    valid_choice=1
                                fi
                            else
                                base_dir="$LOCAL_DIR"
                                valid_dir=1
                                valid_choice=1
                            fi
                        else
                            log "ERROR" "El directorio $LOCAL_DIR no existe o no tiene permisos de escritura."
                        fi
                    done
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
    fi
    
    # Generar nombre del directorio de evidencias
    if [ -n "$CASE_NAME" ]; then
        EVIDENCE_DIR="${base_dir}/EviDump_${CASE_NAME}_${timestamp}"
    else
        EVIDENCE_DIR="${base_dir}/EviDump_${timestamp}"
    fi
    
    # Crear directorios
    mkdir -p "$EVIDENCE_DIR"/{logs,sistema,usuarios,red,archivos,memoria,cronologia,servicios,aplicaciones,dispositivos}
    
    # Verificar si se crearon correctamente
    if [ ! -d "$EVIDENCE_DIR" ]; then
        log "ERROR" "No se pudo crear el directorio de evidencias: $EVIDENCE_DIR"
        exit 1
    fi
    
    # Configurar archivo de registro
    LOG_FILE="${EVIDENCE_DIR}/evidump.log"
    touch "$LOG_FILE"
    
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

# Función para generar un informe resumen
generate_summary() {
    local summary_file="${EVIDENCE_DIR}/resumen_evidencias.txt"
    local end_time=$(date +%s)
    local duration=$((end_time - STARTED_AT))
    local hostname=$(hostname 2>/dev/null || echo "desconocido")
    local os_info=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d= -f2 | tr -d '"' || echo "desconocido")
    local kernel=$(uname -r 2>/dev/null || echo "desconocido")
    
    # Generar resumen
    {
        echo "==========================================================="
        echo "          RESUMEN DE LA RECOLECCIÓN DE EVIDENCIAS          "
        echo "==========================================================="
        echo ""
        echo "FECHA Y HORA DE INICIO: $(date -d @$STARTED_AT "+%Y-%m-%d %H:%M:%S")"
        echo "FECHA Y HORA DE FIN: $(date -d @$end_time "+%Y-%m-%d %H:%M:%S")"
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
        find "$EVIDENCE_DIR" -type d | sort | sed 's|'$EVIDENCE_DIR'|.|' | sed 's/^/  /'
        echo ""
        echo "ARCHIVOS GENERADOS:"
        find "$EVIDENCE_DIR" -type f -name "*.txt" | wc -l | xargs echo "  - Archivos de texto:"
        find "$EVIDENCE_DIR" -type f -name "*.tar.gz" | wc -l | xargs echo "  - Archivos comprimidos:"
        find "$EVIDENCE_DIR" -type f -name "*.bin" | wc -l | xargs echo "  - Archivos binarios:"
        echo ""
        echo "TAMAÑO TOTAL DE EVIDENCIAS: $(du -sh "$EVIDENCE_DIR" | cut -f1)"
        echo ""
        echo "HASH SHA256 DE EVIDENCIAS CLAVE:"
        for file in $(find "$EVIDENCE_DIR" -type f -name "*.tar.gz"); do
            echo "  - $(basename "$file"): $(sha256sum "$file" | cut -d' ' -f1)"
        done
        echo ""
        echo "==========================================================="
        echo "                 FIN DEL INFORME DE EVIDENCIAS             "
        echo "==========================================================="
    } > "$summary_file"
    
    # Calcular hash del resumen
    if command_exists "sha256sum"; then
        sha256sum "$summary_file" > "${summary_file}.sha256"
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
        echo "USUARIO EJECUTANDO SCRIPT: $(whoami)"
        echo ""
        echo "INFORMACIÓN DEL SISTEMA:"
        echo "  - Kernel: $(uname -a 2>/dev/null || echo "N/A")"
        
        if [ -f "/etc/os-release" ]; then
            echo "  - Distribución: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d= -f2 | tr -d '"')"
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
            find /bin -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -d' ' -f1
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
    run_and_save "env" "${EVIDENCE_DIR}/sistema/variables_entorno.txt" "Variables de entorno"
    
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
    run_and_save "ls -la /etc/cron*" "${EVIDENCE_DIR}/cronologia/cron_directorios.txt" "Directorios de cron"
    
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    run_and_save "find /etc/cron* -type f -exec cat {} \;" "${EVIDENCE_DIR}/cronologia/cron_trabajos.txt" "Trabajos de cron"
    
    show_progress "Procesos" $((++current_cmd)) $total_cmds
    run_and_save "crontab -l" "${EVIDENCE_DIR}/cronologia/crontab_root.txt" "Crontab del usuario root"
    
    # Buscar crontabs de usuarios
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            username=$(basename "$user_home")
            if command_exists "crontab"; then
                run_and_save "crontab -u $username -l" "${EVIDENCE_DIR}/cronologia/crontab_${username}.txt" "Crontab del usuario $username"
            fi
        fi
    done
    
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
    run_and_save "find /etc/sudoers.d -type f -exec cat {} \;" "${EVIDENCE_DIR}/usuarios/sudoers_adicional.txt" "Configuración adicional de sudoers"
    
    # Historial de login
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "last" "${EVIDENCE_DIR}/usuarios/last.txt" "Últimos logins"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "lastlog" "${EVIDENCE_DIR}/usuarios/lastlog.txt" "Registro de último login por usuario"
    
    show_progress "Usuarios" $((++current_cmd)) $total_cmds
    run_and_save "w" "${EVIDENCE_DIR}/usuarios/usuarios_activos.txt" "Usuarios actualmente activos"
    
    # Copiar .bash_history de usuarios
    log "INFO" "Copiando historial de comandos de usuarios..."
    
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            username=$(basename "$user_home")
            if [ -f "${user_home}/.bash_history" ]; then
                cp "${user_home}/.bash_history" "${EVIDENCE_DIR}/usuarios/bash_history_${username}.txt" 2>/dev/null
            fi
            
            # Buscar archivos de historial adicionales
            for history_file in "${user_home}/.zsh_history" "${user_home}/.history" "${user_home}/.sh_history"; do
                if [ -f "$history_file" ]; then
                    cp "$history_file" "${EVIDENCE_DIR}/usuarios/$(basename "$history_file")_${username}.txt" 2>/dev/null
                fi
            done
        fi
    done
    
    # Recolectar archivos ssh conocidos
    for user_home in /home/*; do
        if [ -d "$user_home/.ssh" ]; then
            username=$(basename "$user_home")
            mkdir -p "${EVIDENCE_DIR}/usuarios/ssh_${username}"
            cp -r "${user_home}/.ssh/"* "${EVIDENCE_DIR}/usuarios/ssh_${username}/" 2>/dev/null
        fi
    done
    
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
    run_and_save "ls -la /etc/init.d/" "${EVIDENCE_DIR}/servicios/init_scripts.txt" "Scripts init.d"
    
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
        tar -czf "${EVIDENCE_DIR}/logs/logs_completos.tar.gz" -C / var/log 2>/dev/null || 
        log "ERROR" "Error al comprimir los logs"
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
    run_and_save "cat /etc/hosts.allow 2>/dev/null" "${EVIDENCE_DIR}/red/hosts_allow.txt" "Hosts permitidos"
    
    show_progress "Red" $((++current_cmd)) $total_cmds
    run_and_save "cat /etc/hosts.deny 2>/dev/null" "${EVIDENCE_DIR}/red/hosts_deny.txt" "Hosts denegados"
    
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
    
    # Buscar archivos SUID/SGID
    run_and_save "find / -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null" \
                "${EVIDENCE_DIR}/archivos/suid_sgid.txt" "Archivos con SUID/SGID" 300
    
    # Buscar archivos recientemente modificados
    run_and_save "find / -type f -mtime -7 -not -path \"/proc/*\" -not -path \"/sys/*\" -not -path \"/run/*\" -ls 2>/dev/null" \
                "${EVIDENCE_DIR}/archivos/modificados_ultimos_7dias.txt" "Archivos modificados en los últimos 7 días" 300
    
    # Buscar archivos ocultos
    run_and_save "find / -type f -name \".*\" -not -path \"/proc/*\" -not -path \"/sys/*\" -not -path \"/run/*\" -ls 2>/dev/null" \
                "${EVIDENCE_DIR}/archivos/archivos_ocultos.txt" "Archivos ocultos" 300
    
    # Buscar archivos en /tmp
    run_and_save "find /tmp -type f -ls 2>/dev/null" \
                "${EVIDENCE_DIR}/archivos/archivos_tmp.txt" "Archivos en /tmp" 60
    
    # Buscar archivos grandes
    run_and_save "find / -type f -size +100M -not -path \"/proc/*\" -not -path \"/sys/*\" -not -path \"/run/*\" -ls 2>/dev/null" \
                "${EVIDENCE_DIR}/archivos/archivos_grandes.txt" "Archivos mayores a 100MB" 300
    
    # Archivos de inicio sospechosos
    run_and_save "ls -la /etc/rc*.d/" "${EVIDENCE_DIR}/archivos/archivos_rc.txt" "Archivos rc.d"
    
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
    run_and_save "cat /proc/scsi/scsi 2>/dev/null" "${EVIDENCE_DIR}/dispositivos/scsi.txt" "Dispositivos SCSI"
    
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

# Captura de memoria RAM (si volatility está disponible)
collect_memory_image() {
    log "INFO" "Evaluando captura de memoria RAM..."
    
    # Verificar si hay herramientas disponibles para captura de RAM
    if command_exists "lime-forensics"; then
        log "INFO" "lime-forensics encontrado, procediendo con captura de memoria..."
        
        # Para evitar fallos por espacio
        if [ "$AVAILABLE_SPACE" -gt 4000 ]; then  # Necesita al menos 4GB
            kernel_version=$(uname -r)
            run_and_save "lime-forensics format=lime output=${EVIDENCE_DIR}/memoria/ram_dump.lime" \
                        "${EVIDENCE_DIR}/memoria/lime_output.txt" "Captura de memoria con lime-forensics"
        else
            log "WARNING" "Espacio insuficiente para captura de memoria RAM"
        fi
    elif command_exists "fmem"; then
        log "INFO" "fmem encontrado, procediendo con captura de memoria..."
        
        if [ "$AVAILABLE_SPACE" -gt 4000 ]; then  # Necesita al menos 4GB
            run_and_save "dd if=/dev/fmem of=${EVIDENCE_DIR}/memoria/ram_dump.bin bs=1MB" \
                        "${EVIDENCE_DIR}/memoria/fmem_output.txt" "Captura de memoria con fmem"
        else
            log "WARNING" "Espacio insuficiente para captura de memoria RAM"
        fi
    else
        log "INFO" "No se encontraron herramientas para captura de memoria (lime-forensics o fmem)"
        run_and_save "cat /proc/meminfo" "${EVIDENCE_DIR}/memoria/meminfo.txt" "Información de memoria"
    fi
    
    # Capturar información de /proc para análisis similar a volatility
    log "INFO" "Capturando información de /proc para análisis de memoria..."
    
    # Directorio temporal para estructura /proc
    local proc_temp="${EVIDENCE_DIR}/memoria/proc_info"
    mkdir -p "$proc_temp"
    
    # Guardar mapas de memoria de procesos
    for pid in /proc/[0-9]*; do
        if [ -d "$pid" ]; then
            pid_num=$(basename "$pid")
            mkdir -p "${proc_temp}/${pid_num}"
            cp "${pid}/maps" "${proc_temp}/${pid_num}/" 2>/dev/null
            cp "${pid}/status" "${proc_temp}/${pid_num}/" 2>/dev/null
            cp "${pid}/cmdline" "${proc_temp}/${pid_num}/" 2>/dev/null
            cp "${pid}/environ" "${proc_temp}/${pid_num}/" 2>/dev/null
        fi
    done
    
    # Comprimir para ahorrar espacio
    if command_exists "tar"; then
        tar -czf "${EVIDENCE_DIR}/memoria/proc_info.tar.gz" -C "${EVIDENCE_DIR}/memoria" proc_info
        rm -rf "$proc_temp"
    fi
    
    log "SUCCESS" "Captura de información de memoria completada"
}

# Función de limpieza y finalización
cleanup_and_finish() {
    # Calcular hashes de todos los archivos recolectados
    log "INFO" "Calculando hashes de archivos recolectados..."
    
    if command_exists "sha256sum"; then
        find "$EVIDENCE_DIR" -type f -not -name "*.sha256" | while read -r file; do
            sha256sum "$file" >> "${EVIDENCE_DIR}/hashes_sha256.txt"
        done
        log "SUCCESS" "Hashes SHA256 calculados"
    else
        log "WARNING" "No se pudo calcular hashes SHA256 (sha256sum no disponible)"
    fi
    
    # Permisos seguros
    chmod -R 400 "$EVIDENCE_DIR"  # Solo lectura para el propietario
    
    # Tiempo total
    local end_time=$(date +%s)
    local duration=$((end_time - STARTED_AT))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    log "SUCCESS" "Recolección de evidencias completada en $minutes minutos y $seconds segundos"
    log "SUCCESS" "Evidencias guardadas en: $EVIDENCE_DIR"
    
    # Mensaje final
    echo ""
    echo -e "${GREEN}${BOLD}=======================================================${NC}"
    echo -e "${GREEN}${BOLD}           RECOLECCIÓN FINALIZADA CON ÉXITO           ${NC}"
    echo -e "${GREEN}${BOLD}=======================================================${NC}"
    echo ""
    echo -e "${BOLD}Tiempo Total:${NC} $minutes minutos y $seconds segundos"
    echo -e "${BOLD}Directorio de Evidencias:${NC} $EVIDENCE_DIR"
    echo ""
    echo -e "${YELLOW}NOTA:${NC} Asegúrese de mantener seguro el directorio de evidencias"
    echo -e "      para preservar la integridad de la información forense."
    echo ""
}

# Función principal
main() {
    # Mostrar banner
    show_banner
    
    # Verificar privilegios
    check_root
    
    # Parsear argumentos
    parse_arguments "$@"
    
    # Verificar herramientas necesarias
    check_required_tools
    
    # Configurar directorios
    setup_directories
    
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