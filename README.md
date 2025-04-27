# 🔍💾 EviDumpLin - Herramienta de Recolección de Evidencias Forenses para Linux

## Descripción

EviDumpLin es un script avanzado para la recolección de evidencias forenses en sistemas Linux, diseñado para recopilar información exhaustiva del sistema durante investigaciones de incidentes y análisis forenses. La herramienta organiza los datos críticos del sistema en directorios categorizados, preservando la integridad de las evidencias.

## Características Principales

- **Recolección exhaustiva**: Recopila información del sistema, procesos, usuarios, red y servicios
- **Análisis de memoria**: Captura opcional de RAM con herramientas compatibles (lime-forensics/fmem)
- **Salida estructurada**: Organiza evidencias en categorías lógicas (sistema, usuarios, red, logs, etc.)
- **Protección de integridad**: Genera hashes SHA256 para todos los archivos recolectados
- **Interfaz amigable**: Seguimiento de progreso y salida con códigos de color
- **Opciones flexibles**: Guarda evidencias en USB o directorios locales

---

## Instalación y Uso

### Requisitos
- Sistema Linux
- Privilegios de root
- Herramientas básicas de terminal (tar, find, grep, etc.)

### Instalación

Clonar el repositorio:
```bash
git clone https://github.com/Mayky23/EviDumpLin.git
cd EviDumpLin
```

Dar permisos de ejecución:
```bash
chmod +x EviDumpLin.sh
```

### Ejecución
Ejecutar con privilegios root:
```bash
sudo ./EviDumpLin.sh
```

---

## Opciones de Línea de Comando

| Opción         | Descripción             | Ejemplo                          |
|----------------|-------------------------|----------------------------------|
| `-h`, `--help` | Muestra mensaje de ayuda | `./EviDumpLin.sh -h`             |
| `-v`, `--verbose` | Activa salida detallada | `./EviDumpLin.sh -v`             |
| `-c`, `--case` | Especifica nombre del caso | `./EviDumpLin.sh -c caso123`     |
| `-o`, `--output` | Especifica directorio de salida | `./EviDumpLin.sh -o /media/usb` |

---

## Proceso de Recolección

- **Identificación del sistema**: Crea perfil del sistema con detalles de hardware/SO  
- **Información del sistema**: CPU, memoria, disco, kernel y variables de entorno  
- **Análisis de procesos**: Procesos en ejecución, archivos abiertos, tareas cron  
- **Información de usuarios**: Cuentas, sudoers, historial de acceso, historiales bash  
- **Examen de servicios**: Servicios systemd, scripts init, servicios habilitados  
- **Forense de red**: Interfaces, conexiones, reglas de firewall, DNS  
- **Recolección de logs**: Logs del sistema, de autenticación y de aplicaciones  
- **Análisis de archivos**: Archivos sospechosos, binarios SUID/SGID, archivos ocultos  
- **Captura de memoria**: Volcado opcional de RAM (si hay herramientas disponibles)  