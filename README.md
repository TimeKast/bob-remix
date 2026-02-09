# BOB - Monitor de Antigravity

🦞 Monitor y automatización de múltiples instancias de Antigravity.

## Features

- 🔍 **Auto-detección** de ventanas VS Code/Antigravity
- ✅ **Toggle on/off** por instancia
- 📝 **Prompts configurables** (default + custom por instancia)
- 🔄 **Retry automático** (3 intentos antes de notificar)
- 📢 **Discord notifications** para completado/errores
- 🔽 **System tray** para correr en segundo plano

## Requisitos

- **Node.js 18+**
- **Rust** (requerido para build) - [Instalar Rust](https://www.rust-lang.org/tools/install)
- **PowerShell 5.1+**

## Instalación

```powershell
# 1. Instalar Rust (si no lo tienes)
# Visita: https://www.rust-lang.org/tools/install

# 2. Instalar dependencias
cd bob
npm install

# 3. Ejecutar en modo desarrollo
npm run tauri dev

# 4. Build del ejecutable
npm run tauri build
```

## Arquitectura

```
bob/
├── src/                    # Frontend (Svelte)
│   ├── routes/
│   │   └── +page.svelte    # Dashboard principal
│   └── lib/
│       ├── InstanceCard.svelte
│       ├── Settings.svelte
│       ├── store.ts        # Estado global
│       └── types.ts
├── src-tauri/              # Backend (Rust)
│   └── src/
│       └── lib.rs          # Comandos Tauri
├── scripts/                # PowerShell utilities
│   ├── detect-windows.ps1
│   └── paste-prompt.ps1
└── package.json
```

## Uso

1. Abre una o más ventanas de VS Code con Antigravity
2. Ejecuta `npm run tauri dev`
3. Click en "🔍 Scan" para detectar instancias
4. Activa el toggle en las instancias que quieras monitorear
5. La app automáticamente enviará prompts cuando detecte inactividad

## Configuración

Desde Settings (⚙️):
- **Default Prompt**: Texto a enviar por defecto
- **Inactivity Timeout**: Segundos antes de enviar siguiente prompt
- **Max Retries**: Intentos antes de notificar error
- **Discord Webhook**: URL para notificaciones
