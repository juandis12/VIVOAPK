# 🚀 Guía de Release — VivoTv

Guía completa paso a paso para subir una nueva versión de la app y que los usuarios la reciban automáticamente.

---

## ¿Cómo funciona el sistema?

Cuando subes una nueva versión:

1. Subes el nuevo APK a **Supabase Storage**
2. Actualizas un archivo `version.json` en Supabase
3. La próxima vez que un usuario abra la app, ella **detecta la nueva versión automáticamente**
4. Aparece un diálogo preguntando si desea actualizar
5. Al aceptar, **descarga e instala sola** sin intervención manual

> ⚠️ Este sistema solo funciona en **Android**. En iOS no es posible instalar APKs externos.

---

## 📋 Checklist Rápida (para cuando ya sabes hacerlo)

```
☐ 1. Cambiar version en pubspec.yaml (subir el +N)
☐ 2. flutter build apk --release --target-platform android-arm64    flutter build apk --release --target-platform android-arm64
☐ 3. Renombrar APK → vivotv-vX.X.X.apk
☐ 4. Subir APK a Supabase Storage → bucket "updates"
☐ 5. Copiar URL pública del APK
☐ 6. Actualizar version.json con nueva versión y URL
☐ 7. Reemplazar version.json en Supabase Storage
☐ 8. Verificar URL del JSON en el navegador ✅
```

---

## Paso a Paso Detallado

---

### PASO 1 — Haz tus cambios en el código

Modifica el código normalmente. Cuando estés listo para lanzar la nueva versión, sigue los pasos siguientes.

---

### PASO 2 — Sube el número de versión en `pubspec.yaml`

Abre el archivo `pubspec.yaml` (raíz del proyecto) y cambia la línea `version`:

```yaml
# ANTES
version: 1.0.0+1

# DESPUÉS (nueva versión)
version: 1.1.0+2
```

**¿Qué significa cada parte?**

| Parte | Ejemplo | Descripción |
|---|---|---|
| `1.1.0` | Nombre de versión | Lo que ven los usuarios en el diálogo |
| `+2` | Código de versión | Número interno que compara la app para saber si hay actualización |

> ⚠️ **Regla crítica:** El número después del `+` (versionCode) **SIEMPRE debe aumentar** con cada release. Nunca puede repetirse ni bajar.
>
> Ejemplos válidos: `1.0.0+1` → `1.1.0+2` → `1.2.0+3` → `2.0.0+4`

---

### PASO 3 — Compila el APK de producción

Abre la terminal en VS Code (`Ctrl + ñ`) y ejecuta:

```bash
flutter build apk --release
```

Espera entre 2 y 5 minutos. Cuando termine verás algo así:

```
✓ Built build/app/outputs/flutter-apk/app-release.apk (XX.X MB)
```

---

### PASO 4 — Renombra el APK

Navega a la carpeta:
```
build/app/outputs/flutter-apk/
```

Copia el archivo `app-release.apk` a tu escritorio o carpeta de descargas y **renómbralo** usando el número de versión:

```
app-release.apk  →  vivotv-v1.1.0.apk
```

> 💡 Usar el número de versión en el nombre te ayuda a llevar un historial claro de cada release.

---

### PASO 5 — Sube el APK a Supabase Storage

1. Ve a [https://supabase.com/dashboard](https://supabase.com/dashboard)
2. Selecciona tu proyecto (`esnrgviozjfjgnbcrduz`)
3. En el menú izquierdo → **Storage**
4. Abre el bucket **`updates`**
5. Haz clic en **"Upload file"**
6. Selecciona el archivo `vivotv-v1.1.0.apk`
7. Espera que termine de subir

---

### PASO 6 — Copia la URL pública del APK

Una vez subido el APK:

1. En la lista de archivos del bucket, haz clic en los **3 puntos (⋯)** al lado del archivo
2. Selecciona **"Get URL"** o **"Copy URL"**
3. Copia esa URL

La URL tendrá este formato exacto:
```
https://esnrgviozjfjgnbcrduz.supabase.co/storage/v1/object/public/updates/vivotv-v1.1.0.apk
```

---

### PASO 7 — Crea el nuevo `version.json`

En tu PC, crea un archivo de texto llamado `version.json` con este contenido:

```json
{
  "version": "1.1.0",
  "versionCode": 2,
  "downloadUrl": "https://esnrgviozjfjgnbcrduz.supabase.co/storage/v1/object/public/updates/vivotv-v1.1.0.apk",
  "releaseNotes": "Descripción de los cambios de esta versión"
}
```

**Reglas importantes al editar este archivo:**

| Campo | Regla |
|---|---|
| `version` | Debe coincidir con el nombre de versión en `pubspec.yaml` (ej: `"1.1.0"`) |
| `versionCode` | Debe coincidir con el número después del `+` en `pubspec.yaml` (ej: `2`) |
| `downloadUrl` | La URL pública del APK que copiaste en el Paso 6 |
| `releaseNotes` | Texto libre que verá el usuario en el diálogo de actualización |

---

### PASO 8 — Sube el `version.json` a Supabase

1. En Supabase → Storage → bucket **`updates`**
2. Si ya existe un `version.json` antiguo → **selecciónalo** → clic en los 3 puntos → **"Delete"**
3. Clic en **"Upload file"**
4. Sube el nuevo `version.json`

---

### PASO 9 — Verifica que todo funciona

Abre esta URL directamente en tu navegador:

```
https://esnrgviozjfjgnbcrduz.supabase.co/storage/v1/object/public/updates/version.json
```

Debes ver el JSON con los datos correctos. Si ves el JSON → ✅ todo listo.

Si ves un error 404 o de permisos → el archivo no está público o hay un error en el nombre del bucket.

---

## ¿Qué verá el usuario?

La próxima vez que el usuario abra la app (en la pantalla de inicio):

```
┌──────────────────────────────────────┐
│  🚀 Actualización disponible         │
│                                      │
│  Versión 1.1.0                       │
│  "Descripción de los cambios"        │
│                                      │
│  [Ahora no]      [Actualizar]        │
└──────────────────────────────────────┘
```

- Si pulsa **"Ahora no"** → el diálogo se cierra y la app continúa normal
- Si pulsa **"Actualizar"** → descarga automática con barra de progreso → instalación automática de Android

---

## Historial de Versiones (llévalo actualizado)

| Versión | versionCode | Fecha | Cambios |
|---|---|---|---|
| 1.0.0 | 1 | 2026-04-14 | Versión inicial |
| — | — | — | — |

> 💡 Actualiza esta tabla cada vez que hagas un release para llevar un registro ordenado.

---

## Solución de Problemas

### El diálogo de actualización no aparece
- Verifica que el `versionCode` en `version.json` sea **mayor** que el `+N` de la versión instalada
- Verifica la URL del `version.json` en el navegador

### El APK no se instala
- El usuario debe tener activada la opción **"Instalar aplicaciones de fuentes desconocidas"** en Android
- La app pedirá este permiso automáticamente, pero en algunos dispositivos el usuario debe activarlo manualmente en Configuración → Seguridad

### Error al descargar
- Verifica que el APK en Supabase Storage sea público (bucket público)
- Verifica que la URL en `downloadUrl` sea correcta

---

*Última actualización: 2026-04-14*
