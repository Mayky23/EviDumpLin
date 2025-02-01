# 🔎💾 EviDumpLin

Haciendo uso de los comandos internos de Linux he creado este script en bash que permite confeccionar un USB-STICK donde se almacenen evidencias.

El fichero BATCH se lanzará en la máquina que se pretenda peritar. Este shell realiza funciones como copiar registros a la unidad USB externa y recopila información como fecha, hora, usuarios registrados, árbol de procesos, tiempo de actividad del sistema, etc. Todos estos registros se guardan en una carpeta y en formato.txt



# Como utilizar EviDump 

Clonamos la herramienta
```bash
  git clone https://github.com/Mayky23/EviDumpLin.git
```

Accedemos al directorio
```bash
  cd EviDumpLin
```

⚠️ Para utilizar este script le daremos permosos de ejecición

```bash
  chmod +x EviDumpLin.sh
```
Ahora lo ejecutamos 

```bash
  ./EviDumpLin.sh
```

⚠️ En caso de error ⚠️

Usar dos2unix (si está disponible en tu sistema):

Si dos2unix está disponible, puedes convertir el archivo con el siguiente comando:
```bash
  dos2unix EviDumpLin.sh
```
Si dos2unix no está disponible, puedes usar el comando sed para eliminar los caracteres ^M:
```bash
  sed -i 's/\r//' EviDumpLin.sh
```
Ahora ejecutamos la herramienta
```bash
  chmod +x EviDumpLin.sh
./EviDumpLin.sh
```

Pantalla principal

![Pantalla principal de la herramienta](img/img1.png)

Seleccionamos la ruta donde se guardarán las evidencias

![Ruta de guardado](img/img2.png)

Comienzan a generarse las evidencias

![Generacion de evidencias](img/img3.png)

Y una vez completado el proceso por completo veremos lo siguiente: 
 
![Finalización del proceso](img/img4.png)

Ahora podremos comprobar todas las evidencias clasificadas por carpetas 
#
SECCIONES DE LAS EVIDENCIAS

![Evidencias](img/img5.png)

ARCHIVOS

![Evidencias](img/img6.png)

LOGS

![Evidencias](img/img7.png)

RED

![Evidencias](img/img8.png)

SISTEMA

![Evidencias](img/img9.png)

USUARIOS

![Evidencias](img/img10.png)
