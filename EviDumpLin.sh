#!/bin/bash
# -------------------------------------------------------
# SCRIPT DE RECOLECCIÓN DE EVIDENCIAS EN VIVO (LINUX)
# -------------------------------------------------------

# Banner de inicio con printf
printf "%s\n" " ______     _ _____                        _      _       "
printf "%s\n" "|  ____|   (_)  __ \                      | |    (_)      "
printf "%s\n" "| |____   ___| |  | |_   _ _ __ ___  _ __ | |     _ _ __  "
printf "%s\n" "|  __\ \ / / | |  | | | | | '_ \ _ \\| '_ \\| |    | | '_ \\ "
printf "%s\n" "| |___\ V /| | |__| | |_| | | | | | | |_) | |____| | | | |"
printf "%s\n" "|______\_/ |_|_____/ \__,_|_| |_| |_| .__/|______|_|_| |_| "
printf "%s\n" "                                     | |                   "
printf "%s\n" "                                     |_|                   "
printf "%s\n" ""
printf "%s\n" "---- By: MARH ---------------------------------------------"
echo ""

# Función para verificar si el comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. Solicitar al usuario la ubicación para guardar las evidencias
echo "============================================"
echo "||  ¿Dónde desea guardar las evidencias?  ||"
echo "||                                        ||"
echo "||  1. En un dispositivo USB              ||"
echo "||  2. En un directorio local             ||"
echo "============================================"
read -p "Ingrese el número de opción (1 o 2): " choice

# Variables para la ruta de las evidencias
TIMESTAMP=$(date +%d_%m_%Y_%H_%M_%S)

if [ "$choice" -eq 1 ]; then
    # Opción 1: Guardar en un dispositivo USB
    read -p "Ingrese el punto de montaje del USB (por ejemplo, /media/usb): " USB_MOUNT
    if [ -d "$USB_MOUNT" ]; then
        EVIDENCE_DIR="${USB_MOUNT}/Evidencias_${TIMESTAMP}"
        echo "Las evidencias se guardarán en: ${EVIDENCE_DIR}"
    else
        echo "ERROR: El punto de montaje $USB_MOUNT no existe o no es válido."
        exit 1
    fi
elif [ "$choice" -eq 2 ]; then
    # Opción 2: Guardar en un directorio local
    read -p "Ingrese la ruta del directorio local (por ejemplo, /tmp): " LOCAL_DIR
    if [ -d "$LOCAL_DIR" ]; then
        EVIDENCE_DIR="${LOCAL_DIR}/Evidencias_${TIMESTAMP}"
        echo "Las evidencias se guardarán en: ${EVIDENCE_DIR}"
    else
        echo "ERROR: El directorio $LOCAL_DIR no existe."
        exit 1
    fi
else
    echo "Opción no válida. Por favor, seleccione 1 o 2."
    exit 1
fi

# Crear el directorio de evidencias
mkdir -p "$EVIDENCE_DIR/logs" "$EVIDENCE_DIR/sistema" "$EVIDENCE_DIR/usuarios" "$EVIDENCE_DIR/red" "$EVIDENCE_DIR/archivos" || { echo "ERROR: No se pudo crear el directorio ${EVIDENCE_DIR}"; exit 1; }

# Función para ejecutar comandos y guardar resultados
run_and_save() {
    local cmd="$1"
    local outfile="$2"
    
    echo "Ejecutando: ${cmd}"  # Mensaje de progreso
    
    # Redirigir salida del comando a archivo
    {
        echo "===================================================="
        echo "COMANDO: ${cmd}"
        echo "FECHA DE EJECUCIÓN: $(date)"
        echo "===================================================="
        $cmd
        echo -e "\n\n"
    } >> "${outfile}" 2>&1
}

# 3. COPIA DE LOGS DEL SISTEMA
echo "[*] Copiando directorio /var/log ..."
if command_exists "tar"; then
    tar -czf "${EVIDENCE_DIR}/logs/logs.tar.gz" -C / var/log 2>/dev/null
else
    cp -r /var/log "${EVIDENCE_DIR}/logs" 2>/dev/null
fi
sleep 5  # Espera 5 segundos para asegurar que la copia de los logs se complete

# 4. OBTENER INFORMACIÓN DEL SISTEMA (Guardado en la carpeta 'sistema')
run_and_save "date" "${EVIDENCE_DIR}/sistema/fecha.txt"
sleep 2  # Pausa de 2 segundos

run_and_save "hostname" "${EVIDENCE_DIR}/usuarios/hostname.txt"  # Modificado: guardado en 'usuarios'
sleep 2

run_and_save "lscpu" "${EVIDENCE_DIR}/sistema/cpuinfo.txt"
sleep 2

run_and_save "ps aux" "${EVIDENCE_DIR}/sistema/procesos_en_ejecucion.txt"
sleep 3  # Pausa un poco más debido a que ps puede generar muchos datos

run_and_save "ps auxf" "${EVIDENCE_DIR}/sistema/arbol_procesos.txt"
sleep 3

run_and_save "mount" "${EVIDENCE_DIR}/sistema/sistema_montado.txt"
sleep 2

run_and_save "fdisk -l" "${EVIDENCE_DIR}/sistema/fdisk_l.txt"
sleep 3

run_and_save "parted -l" "${EVIDENCE_DIR}/sistema/parted_l.txt"
sleep 3

run_and_save "df -h" "${EVIDENCE_DIR}/sistema/uso_disco.txt"
sleep 2

run_and_save "lsmod" "${EVIDENCE_DIR}/sistema/modulos_cargados.txt"
sleep 2

run_and_save "cat /proc/cmdline" "${EVIDENCE_DIR}/sistema/kernel_cmdline.txt"
sleep 2

run_and_save "uptime" "${EVIDENCE_DIR}/sistema/tiempo_actividad.txt"
sleep 2

run_and_save "uname -a" "${EVIDENCE_DIR}/sistema/info_sistema.txt"
sleep 2

run_and_save "cat /etc/*-release" "${EVIDENCE_DIR}/sistema/info_distribucion.txt"
sleep 2

run_and_save "env" "${EVIDENCE_DIR}/sistema/variables_entorno.txt"
sleep 2

run_and_save "free -m" "${EVIDENCE_DIR}/sistema/memoria_en_uso.txt"
sleep 2

run_and_save "systemctl list-units --type=service --all" "${EVIDENCE_DIR}/sistema/servicios_ejecucion.txt"
sleep 3

run_and_save "cat /etc/passwd" "${EVIDENCE_DIR}/sistema/passwd.txt"
sleep 2

run_and_save "cat /etc/group" "${EVIDENCE_DIR}/usuarios/group.txt"  # Modificado: guardado en 'usuarios'
sleep 2

run_and_save "lastlog" "${EVIDENCE_DIR}/sistema/lastlog.txt"
sleep 2

run_and_save "whoami" "${EVIDENCE_DIR}/usuarios/usuario_ejecutando.txt"  # Modificado: guardado en 'usuarios'
sleep 2

run_and_save "logname" "${EVIDENCE_DIR}/usuarios/usuario_logname.txt"  # Modificado: guardado en 'usuarios'
sleep 2

run_and_save "id" "${EVIDENCE_DIR}/usuarios/usuario_id.txt"  # Modificado: guardado en 'usuarios'
sleep 2

# 5. COPIA DE .bash_history DE CADA USUARIO (Guardado en la carpeta 'usuarios')
echo "[*] Copiando .bash_history de cada usuario en /home/ ..."
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        if [ -f "${user_home}/.bash_history" ]; then
            cp "${user_home}/.bash_history" "${EVIDENCE_DIR}/usuarios/bash_history_${username}" 2>/dev/null
        fi
    fi
done
sleep 3  # Pausa después de la copia de los archivos .bash_history

# 6. RECOLECCIÓN DE INFORMACIÓN DE RED (Guardado en la carpeta 'red')
if command_exists "netstat"; then
    run_and_save "netstat -tulpn" "${EVIDENCE_DIR}/red/conexiones_red_netstat.txt"
else
    echo "[*] netstat no encontrado, utilizando ss."
    run_and_save "ss -tulpn" "${EVIDENCE_DIR}/red/conexiones_red_ss.txt"
fi
sleep 3

run_and_save "ip link show" "${EVIDENCE_DIR}/red/interfaces_red.txt"
sleep 2

run_and_save "netstat -s" "${EVIDENCE_DIR}/red/estadisticas_sockets.txt"
sleep 2

run_and_save "ip -s link show" "${EVIDENCE_DIR}/red/estadisticas_ip_link.txt"
sleep 2

run_and_save "netstat -r" "${EVIDENCE_DIR}/red/tabla_ruteo.txt"
sleep 2

run_and_save "ip route" "${EVIDENCE_DIR}/red/ip_route.txt"
sleep 2

run_and_save "arp -a" "${EVIDENCE_DIR}/red/tabla_arp.txt"
sleep 2

run_and_save "ifconfig -a" "${EVIDENCE_DIR}/red/ifconfig_a.txt"
sleep 2

run_and_save "cat /etc/hosts.allow" "${EVIDENCE_DIR}/red/hosts_allow.txt"
sleep 2

run_and_save "cat /etc/hosts.deny" "${EVIDENCE_DIR}/red/hosts_deny.txt"
sleep 2

run_and_save "cat /etc/hosts" "${EVIDENCE_DIR}/red/hosts.txt"
sleep 2

run_and_save "cat /etc/resolv.conf" "${EVIDENCE_DIR}/red/resolv_conf.txt"
sleep 2

# 7. BUSCAR FICHEROS SUID/SGID (Guardado en la carpeta 'archivos')
echo "[*] Buscando ficheros con SUID/SGID..."
run_and_save "find / -type f \( -perm -4000 -o -perm -2000 \) -ls 2>/dev/null" \
             "${EVIDENCE_DIR}/archivos/ficheros_suid_sgid.txt"
sleep 3  # Pausa después de la búsqueda

# -------------------------------------------------------
# FINALIZACIÓN
# -------------------------------------------------------
echo "==================================================="
echo " RECOLECCIÓN FINALIZADA "
echo " Los archivos de evidencia se guardaron en:"
echo "   ${EVIDENCE_DIR}"
echo "==================================================="

exit 0
