# 🔎💾 EviDumpLin

Haciendo uso de los comandos internos de Linux he creado este script en bash que permite confeccionar un USB-STICK donde se almacenen evidencias.

El fichero BATCH se lanzará en la máquina que se pretenda peritar. Este shell realiza funciones como copiar registros a la unidad USB externa y recopila información como fecha, hora, usuarios registrados, árbol de procesos, tiempo de actividad del sistema, etc. Todos estos registros se guardan en una carpeta y en formato.txt



# Como utilizar EviDump 

⚠️ Para utilizar este script le daremos permosos de ejecición

```bash
  chmod +x EviDumpLin.sh
```
Ahora lo ejecutamos 

```bash
  ./EviDumpLin.sh
```
Pantalla principal

![Pantalla principal de la herramienta](img/img1.png)

Seleccionamos la ruta donde se guardarán las evidencias

![Comienzan a generarse las evidencias](img/img2.png)

Y una vez completado el proceso por completo veremos lo siguiente: 
 
![Finalización del proceso](img/img3.png)

Ahora podremos comprobar todas las evidencias clasificadas por carpetas 
![Evidencias](img/img4.png)
![Evidencias](img/img5.png)
![Evidencias](img/img6.png)
![Evidencias](img/img7.png)
![Evidencias](img/img8.png)
Esta ultima no muestra datos devido a que solo hay un usuario (Aunque queda pendiente su revisión en versiones posteriores)
![Evidencias](img/img9.png)
