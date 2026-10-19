# Mezcla · 0.2.0

App nativa para macOS que permite controlar el volumen, silenciar y elegir la salida de audio de cada aplicación desde la barra de menú. Esta primera versión está compilada para Apple Silicon y fue probada en macOS Tahoe 26.6.2.

## Descargar

La versión de prueba está disponible en [Releases](https://github.com/XbaxS/Mezcla/releases). Descarga `Mezcla-0.2.0.zip`, descomprímelo y abre la aplicación. Requiere un Mac con Apple Silicon y macOS 14.4 o posterior. La app tiene firma local y no está notarizada por Apple.

## Novedades de 0.2.0

- Oculta PowerChime, sonidos del sistema, asistentes y servicios internos de macOS.
- Identifica los procesos auxiliares de Safari como **Safari**, con su icono, en lugar de “Safari Graphics and Media”.
- Conserva los ajustes anteriores de Safari al cambiar su identificación, sin sobrescribir ajustes nuevos.
- Aclara que el control del navegador afecta a **todas las pestañas**. No muestra nombres de sitios inferidos: Core Audio entrega el proceso de audio, no la URL. La identificación fiable de YouTube u otro sitio requiere una integración adicional con el navegador y no está incluida en esta versión.

## Uso

1. Abre **Mezcla.app**. También puedes moverla a Aplicaciones.
2. Reproduce música o un video: la aplicación aparecerá en la lista.
3. Enciende el interruptor de esa aplicación para controlar su audio. Si macOS solicita acceso al audio del sistema, autorízalo para que funcione.
4. Ajusta el volumen, pulsa el parlante para silenciar o elige la salida en el menú.
5. Puedes cerrar la ventana y volver a abrir los controles desde el icono de los tres deslizadores en la barra superior.

**Desactivar** devuelve todas las aplicaciones a su audio original. **Salir de Mezcla** también restaura el audio. Volumen, silencio, salida e interruptor de cada aplicación se recuerdan entre aperturas.

Ejemplo: en Spotify selecciona el JBL; en Safari selecciona las bocinas del Mac. Las dos aplicaciones pueden tener volúmenes distintos. El volumen de Mezcla actúa sobre el volumen que ya tenga cada aplicación y sigue dependiendo del volumen físico de la salida.

## Alcance del prototipo

- Control de 0 a 100 %, silencio y una salida por aplicación.
- Salidas físicas o virtuales que macOS exponga como dispositivos de audio compatibles.
- Revisión de dispositivos y aplicaciones cada dos segundos.
- Si una salida seleccionada desaparece, se libera el control y se restaura el audio original de esa app; aparece un aviso.
- Al dormir el Mac se liberan las rutas y al despertar se vuelven a crear.
- Los navegadores reúnen sus pestañas bajo una misma aplicación. Los servicios auxiliares sin una aplicación identificable se ocultan.
- Está pendiente una prueba prolongada de estabilidad, desconexiones Bluetooth y contenido protegido. No incluye ecualizador, amplificación por encima de 100 % ni inicio automático.

El audio se procesa en memoria. No se graba ni se transmite por internet. Las preferencias se guardan localmente. No se modifica la salida predeterminada del sistema ni se instala un controlador permanente.

## Validación realizada

- Compilación local y firma ad hoc verificadas.
- Interfaz comprobada en el Mac: detección de Spotify, volumen, silencio y selección entre JBL Flip 6 y bocinas del MacBook Air.
- Pruebas deterministas del procesamiento: ganancia, transición a silencio, estéreo, mono, buffers separados, entradas vacías y cortas, exclusión de entradas físicas y limpieza de canales adicionales.
- Pruebas de filtrado de servicios, identificación de Safari sin confundir otros clientes WebKit y migración de preferencias.
- Prueba de integración con dos procesos sintéticos simultáneos sobre BlackHole 2ch: volúmenes independientes al 25 % y 50 %, silencio de la primera fuente conservando la segunda, y recuperación de ambas al retirar los controles. La prueba mide amplitudes de tonos, sin guardar audio.

La validación de la interfaz y de las señales no sustituye una comprobación auditiva con tus aplicaciones y dispositivos habituales.

## Código y compilación

Requiere las herramientas de línea de comandos de Xcode y un SDK con Core Audio Process Taps.

```sh
git clone https://github.com/XbaxS/Mezcla.git
cd Mezcla
./build.sh
./test.sh
```

`build.sh` crea `Mezcla.app` junto a esta carpeta. La firma es local, sin certificado Developer ID ni notarización para distribución pública. Los archivos temporales de compilación se guardan en la carpeta temporal del sistema; se puede elegir otra con `MEZCLA_BUILD_DIR`.

El motor utiliza un tap privado por aplicación, un dispositivo agregado privado con la salida elegida y ganancia atómica con transiciones suaves. El callback de audio no reserva memoria ni usa bloqueos. Las rutas se destruyen al desactivar el control o cerrar la app.

Los archivos `Tests/AudioTests.m` y `Tests/Integration.m` contienen las comprobaciones de procesamiento e integración. La segunda requiere BlackHole 2ch ya instalado y acceso de macOS a audio. No lo instala ni cambia la salida global.

Referencia de la API: [Core Audio taps — Apple](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
