# 🔍💾 EviDumpLin - Herramienta de Recolección de Evidencias Forenses para Linux

## Descripción

EviDumpLin es un script avanzado para la recolección de evidencias forenses en sistemas Linux, diseñado para recopilar información exhaustiva del sistema durante investigaciones de incidentes y análisis forenses. La herramienta organiza los datos críticos del sistema en directorios categorizados, preservando la integridad de las evidencias.

## Características Principales

- **Recolección exhaustiva**: Recopila información del sistema, procesos, usuarios, red y servicios
- **Análisis de memoria**: Captura opcional de RAM con AVML, LiME o fmem (ver [Captura de memoria RAM](#captura-de-memoria-ram)) e información de procesos desde `/proc`
- **Salida estructurada**: Organiza evidencias en categorías lógicas (sistema, usuarios, red, logs, etc.)
- **Protección de integridad**: Genera hashes SHA256 verificables (rutas relativas) para todos los archivos recolectados
- **Cierre seguro**: Si se interrumpe (Ctrl+C), genera igualmente el resumen y los hashes de lo recolectado
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
| `-h`, `--help` | Muestra mensaje de ayuda (no requiere root) | `./EviDumpLin.sh -h`             |
| `-v`, `--verbose` | Activa salida detallada | `./EviDumpLin.sh -v`             |
| `-c`, `--case` | Especifica nombre del caso (letras, números, `.`, `-`, `_`) | `./EviDumpLin.sh -c caso123`     |
| `-o`, `--output` | Especifica directorio de salida | `./EviDumpLin.sh -o /media/usb` |

---
## Estructura del Directorio de Evidencias

```
EviDump_[CASO]_[FECHAHORA]/
├── aplicaciones/
├── archivos/
├── cronologia/
├── dispositivos/
├── logs/
├── memoria/
├── red/
├── servicios/
├── sistema/
├── usuarios/
├── evidump.log
├── hashes_cierre.sha256
├── hashes_sha256.txt
├── identificacion_sistema.txt
├── resumen_evidencias.txt
└── resumen_evidencias.txt.sha256
```

### Verificar la integridad de las evidencias

```bash
cd EviDump_[CASO]_[FECHAHORA]
sha256sum -c hashes_sha256.txt      # todos los archivos recolectados
sha256sum -c hashes_cierre.sha256   # el log y el propio archivo de hashes
```

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

---

## Captura de memoria RAM

La captura de RAM es opcional y se realiza si se detecta alguna de estas herramientas (en este orden):

1. **[AVML](https://github.com/microsoft/avml)**: binario estático; basta con que `avml` esté en el `PATH`.
2. **[LiME](https://github.com/504ensicsLabs/LiME)**: módulo del kernel. Se usa el archivo `lime*.ko` situado junto al script o el módulo `lime` instalado para el kernel en ejecución.
3. **fmem**: si el dispositivo `/dev/fmem` está disponible.

Se requiere espacio libre en el destino de al menos el tamaño de la RAM más un 10%.
