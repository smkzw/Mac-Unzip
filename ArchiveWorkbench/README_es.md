# Mac Unzip

> **Abre cualquier archivo. Doblega la compresión a tu voluntad.**
> Un motor de descompresión de estética cyberpunk, forjado en Swift nativo para el Mac moderno.

[English](README.md) | [中文](README_zh.md) | [Français](README_fr.md) | **[Español](README_es.md)** | [Italiano](README_it.md) | [日本語](README_ja.md) | [한국어](README_ko.md)

---

**Mac Unzip** es una utilidad de archivos nativa para macOS, construida desde cero con **Swift 6.2** y **SwiftUI**, y optimizada para **Apple Silicon**. Abre, crea y protege archivos en todos los formatos que importan — ZIP, 7z, RAR, TAR, DMG e ISO — sin salir nunca del Mac en el que confías.

Sin Electron. Sin entornos de ejecución empaquetados. Sin telemetría. Solo una herramienta rápida y precisa que hace una cosa, y la hace excepcionalmente bien.

## Características

### Formatos
- **Abrir:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO
- **Crear:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST
- **Cifrar:** protección AES-256 para archivos ZIP y 7z

### Flujo de trabajo
- **Arrastrar y soltar** archivos en cualquier parte de la ventana para extraerlos o previsualizarlos
- **Extensión Finder Sync** — clic derecho sobre cualquier archivo o carpeta para comprimirlo o abrirlo
- **Vista previa integrada** — consulta imágenes, PDF, vídeo, texto y Markdown sin extraer todo el archivo
- **Soporte multi-ventana** para gestionar varios archivos a la vez
- **Modo oscuro / claro** que sigue la apariencia del sistema

### Seguridad y fiabilidad
- **Extracción segura** con protección frente a zip-slip y traversía de rutas
- **Rechazo de enlaces simbólicos** y presupuestos de recursos para frenar archivos maliciosos
- **Diario de recuperación ante fallos** — las extracciones interrumpidas se reanudan en lugar de corromperse
- **Cifrado AES-256** para tus archivos ZIP y 7z más sensibles

## Capturas de pantalla

![Mac Unzip](Assets/Logo.svg)

## Instalación

### Requisitos
- **macOS 26** o posterior
- Mac con **Apple Silicon** (serie M)
- **Xcode 26** para compilar desde el código fuente

### Compilar desde el código fuente

```bash
git clone https://github.com/smkzw/Mac-Unzip.git
cd ArchiveWorkbench
xcodegen generate
open MacUnzip.xcodeproj
```

Selecciona el esquema **App**, elige tu dispositivo de destino y pulsa **⌘R** en Xcode 26.

También encontrarás un `MacUnzip-1.0.7.dmg` precompilado en la raíz del repositorio para una evaluación rápida.

## Requisitos del sistema

| Componente | Mínimo |
| --- | --- |
| Sistema operativo | macOS 26 |
| Arquitectura | Apple Silicon (arm64) |
| Herramientas de compilación | Xcode 26, Swift 6.2 |
| Espacio en disco | ~150 MB para la aplicación |

## Licencia

**El uso personal es GRATUITO.** El uso comercial o empresarial requiere una licencia de pago.

- Uso personal, educativo y en proyectos open source sin ánimo de lucro — gratuito
- Uso en empresas, por autónomos, para clientes o con fines lucrativos — [licencia de pago requerida](LICENSE)

Consulta el archivo [LICENSE](LICENSE) para conocer los términos completos.

---

© 2026 smkzw. Todos los derechos reservados.
