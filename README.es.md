# agy-config-sync (Español)

[![GitHub Template](https://img.shields.io/badge/GitHub-Plantilla-blue?style=flat&logo=github)](https://github.com/Tezcatlipocaa/agy-config-sync/generate)
[![Licencia: MIT](https://img.shields.io/badge/Licencia-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Plataforma: Windows | macOS | Linux](https://img.shields.io/badge/Plataforma-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com/Tezcatlipocaa/agy-config-sync)

Sincronización multi-máquina y curación asistida por Inteligencia Artificial para **Google Antigravity CLI (`agy`)**.

[👉 Read documentation in English (README.md)](README.md)

---

## Características Principales

- 🔄 **Sincronización Multi-Máquina**: Conectá y armonizá $1 \dots N$ computadoras (notebook del trabajo, PC gamer de casa, servidor) sin perder configuraciones específicas de cada máquina.
- 🤖 **Curación Asistida por Agente**: Abrí `agy` dentro del repositorio y dejá que el agente analice las capturas de todas tus máquinas para construir una configuración maestra compartida.
- 🛡️ **Guardián Zero-Leak**: Hooks de pre-commit bloquean automáticamente claves API, tokens y rutas personales. Los secretos se mantienen en tu `.env.local`.
- ⚡ **Auto-Descubrimiento**: Clasifica automáticamente tus plugins en copia directa (livianos), repositorios Git con commits fijados, o plantillas con variables.
- 💻 **Multiplataforma**: Paridad total entre Windows PowerShell (`sync.ps1`) y macOS/Linux Bash (`sync.sh`).

---

## Inicio Rápido en 3 Pasos

### 1. Creá tu repositorio privado
Hacé clic en **[Use this template](https://github.com/Tezcatlipocaa/agy-config-sync/generate)** en GitHub para crear tu repositorio privado, luego clonalo:

```bash
# Windows PowerShell:
git clone https://github.com/<tu-usuario>/<tu-repo>.git C:\Users\<tu-usuario>\agy-config-sync
cd C:\Users\<tu-usuario>\agy-config-sync

# macOS / Linux / WSL:
git clone https://github.com/<tu-usuario>/<tu-repo>.git ~/.agy-config-sync
cd ~/.agy-config-sync
```

### 2. Capturá tu computadora actual (No destructivo)
```bash
# Windows:
.\sync.ps1 snapshot -Profile mi-pc-principal

# macOS / Linux:
./sync.sh snapshot mi-pc-principal
```
Commiteá y enviá tu snapshot inicial:
```bash
git add .
git commit -m "feat: captura inicial de mi-pc-principal"
git push
```

### 3. En cualquier otra computadora:
Repetí la clonación, ejecutá `snapshot`, y abrí `agy` para fusionar y alinear tus computadoras:
```bash
# Abrir Antigravity CLI en esta carpeta:
agy
```
Pedile al agente:
> *"Compará los snapshots de todas mis computadoras registradas y prepará la configuración maestra"*

Finalmente, cerrá `agy` y aplicá:
```bash
# Windows:
.\sync.ps1 apply

# macOS / Linux:
./sync.sh apply
```

---

## Referencia de Comandos

| Comando (PowerShell / Bash) | Descripción |
| :--- | :--- |
| `.\sync.ps1 status` / `./sync.sh status` | Muestra el host actual, perfil detectado y estado de staging |
| `.\sync.ps1 add-machine <nombre>` / `./sync.sh add-machine <nombre>` | Registra un alias para la máquina en `host-map.json` |
| `.\sync.ps1 snapshot` / `./sync.sh snapshot` | Captura el estado de `~/.gemini` sin datos personales ni secretos |
| `.\sync.ps1 stage` / `./sync.sh stage` | Construye la carpeta `staging/` para la computadora activa |
| `.\sync.ps1 apply [-DryRun]` / `./sync.sh apply [--dry-run]` | Aplica la configuración en `~/.gemini` (requiere `agy` cerrado) |

---

## Licencia
MIT © Dario
