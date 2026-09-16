# Guía de replicación — IRIS105 en Docker desde cero

Esta guía permite levantar una instancia completa de IRIS105 (API REST + modelo ML + chat app) en cualquier máquina con Docker, sin dependencias previas de IRIS.

---

## Requisitos

- Docker Desktop (Mac/Windows) o Docker Engine (Linux) — versión 24+
- Git
- Python 3.10+ (solo para desarrollo local del chat; no necesario si todo va en Docker)
- Clave Anthropic API (`sk-ant-...`) para el módulo de chat

---

## Imagen Docker de IRIS

```bash
docker pull intersystemsdc/irishealth-ml-community:latest
```

Esta imagen incluye IRIS 2024.1 con IntegratedML (`%AutoML`) habilitado.

---

## Paso 1 — Clonar el repositorio

```bash
git clone https://github.com/<tu-org>/iris105.git
cd iris105
```

---

## Paso 2 — Levantar el contenedor IRIS

```bash
docker run -d \
  --name noshow-iris \
  -p 52773:52773 \
  -p 1972:1972 \
  intersystemsdc/irishealth-ml-community:latest
```

Verificar que arrancó:
```bash
docker ps | grep noshow-iris
curl http://localhost:52773/csp/sys/UtilHome.csp  # debe responder 200
```

Management Portal: `http://localhost:52773/csp/sys/UtilHome.csp`  
Credenciales por defecto: `SuperUser / SYS` (cambiar en producción).

---

## Paso 3 — Crear namespace MLTEST

```bash
docker exec -it noshow-iris iris session IRIS -U %SYS
```

Dentro de la sesión IRIS:
```objectscript
Set dbprops("Directory")="/durable/mgr/mltestdata/"
Do ##class(Config.Databases).Create("MLTESTDATA",.dbprops)
Set nsprops("Globals")="MLTESTDATA"
Set nsprops("Routines")="MLTESTDATA"
Do ##class(Config.Namespaces).Create("MLTEST",.nsprops)
Do ##class(%EnsembleMgr).EnableNamespace("MLTEST",1)
Halt
```

> `%SYS.Namespace` no tiene método `Create` en 2026.1 (`<METHOD DOES NOT EXIST>`;
> existía en versiones anteriores). El equivalente vigente es `Config.Databases` +
> `Config.Namespaces`.

O en una sola línea desde bash, por stdin (el argumento posicional se interpreta como
nombre de rutina y devuelve `<INVALID ARGUMENT>`, el código va por stdin):
```bash
docker exec -i noshow-iris iris session IRIS -U '%SYS' <<'EOF'
Set dbprops("Directory")="/durable/mgr/mltestdata/"
Do ##class(Config.Databases).Create("MLTESTDATA",.dbprops)
Set nsprops("Globals")="MLTESTDATA"
Set nsprops("Routines")="MLTESTDATA"
Do ##class(Config.Namespaces).Create("MLTEST",.nsprops)
Do ##class(%EnsembleMgr).EnableNamespace("MLTEST",1)
Halt
EOF
```

---

## Paso 4 — Copiar y compilar fuentes ObjectScript

```bash
# Copiar clases al contenedor
docker cp src/IRIS105 noshow-iris:/tmp/IRIS105
docker cp src/GCSP    noshow-iris:/tmp/GCSP

# Compilar desde sesión IRIS en namespace MLTEST
docker exec -i noshow-iris iris session IRIS -U MLTEST <<'EOF'
Do $system.OBJ.LoadDir("/tmp/IRIS105","ckr",,1)
Do $system.OBJ.LoadDir("/tmp/GCSP","ckr")
Halt
EOF
```

Verificar:
```bash
docker exec -i noshow-iris iris session IRIS -U MLTEST <<'EOF'
Write $system.OBJ.IsUpToDate("IRIS105.REST.NoShowService"), !
Halt
EOF
# → 1
```

---

## Paso 5 — Crear Web Applications y configurar globals

```bash
docker exec -i noshow-iris iris session IRIS -U MLTEST <<'EOF'
Do ##class(IRIS105.Util.WebAppSetup).ConfigureAll()
Do ##class(IRIS105.Util.ProjectSetup).Init()
Halt
EOF
```

Esto crea:
- `/csp/mltest` → REST API (`IRIS105.REST.NoShowService`)
- `/csp/mltest2` → CSP pages (`GCSP.Basic`, `GCSP.Agenda`) sin DispatchClass
- Token por defecto: `^IRIS105("API","Tokens","demo-readonly-token") = 1`

Agregar tokens adicionales si es necesario:
```bash
docker exec -i noshow-iris iris session IRIS -U MLTEST <<'EOF'
Set ^IRIS105("API","Tokens","mi-token-seguro")=1
Halt
EOF
```

---

## Paso 6 — Generar datos mock

```bash
docker exec -i noshow-iris iris session IRIS -U MLTEST <<'EOF'
Do ##class(IRIS105.Util.MockData).Generate()
Halt
EOF
```

Con parámetros personalizados (via API REST, después del paso 7):
```bash
curl -X POST http://localhost:52773/csp/mltest/api/ml/mock/generate \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" \
  -d '{"months":3,"targetOccupancy":0.85,"patients":200,"clearBeforeGenerate":1,
       "specialtyNoShowRates":{"SPEC-1":0.12,"SPEC-2":0.20,"SPEC-3":0.08}}'
```

---

## Paso 7 — Entrenar el modelo IntegratedML

Opción A — via script SQL:
```bash
docker cp sql/NoShow_model.sql noshow-iris:/tmp/NoShow_model.sql
docker exec -i noshow-iris iris session IRIS -U MLTEST <<'EOF'
Do ##class(%File).ReadAllTextFile("/tmp/NoShow_model.sql",.sql) ...
Halt
EOF
```

Opción B — via API REST (paso a paso):
```bash
# Paso 1: verificar modelo existente
curl -X POST http://localhost:52773/csp/mltest/api/ml/model/step/execute \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" -d '{"step":1}'

# Paso 2: crear modelo
curl -X POST http://localhost:52773/csp/mltest/api/ml/model/step/execute \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" -d '{"step":2}'

# Paso 3: entrenar (puede tardar 1-2 min)
curl -X POST http://localhost:52773/csp/mltest/api/ml/model/step/execute \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" -d '{"step":3}'

# Paso 4: validar
curl -X POST http://localhost:52773/csp/mltest/api/ml/model/step/execute \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" -d '{"step":4}'

# Paso 5: ver métricas
curl -X POST http://localhost:52773/csp/mltest/api/ml/model/step/execute \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" -d '{"step":5}'
```

Verificar que el modelo quedó entrenado:
```bash
curl http://localhost:52773/csp/mltest/api/ml/stats/model \
  -H "Authorization: Bearer demo-readonly-token"
# → defaultTrainedModel: "NoShowModel2_t1" (o t2, t3...)
```

---

## Paso 8 — Instalar y configurar iris105-chat (chat app)

### 8.1 Copiar archivos al contenedor

```bash
docker cp iris105-chat noshow-iris:/opt/iris105-chat
```

### 8.2 Crear `.env` dentro del contenedor

> `docker exec bash -c 'cat > ...'` falla con **Permission denied** si el directorio fue copiado con `docker cp` desde Mac (pertenece al usuario 501 del host, no a `irisowner`). Usar `docker cp` desde el host:

```bash
cat > /tmp/iris105-chat.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-...tu-clave-aqui...
IRIS_BASE_URL=http://localhost:52773/csp/mltest
IRIS_TOKEN=demo-readonly-token
EOF
docker cp /tmp/iris105-chat.env noshow-iris:/opt/iris105-chat/.env
rm /tmp/iris105-chat.env
```

### 8.3 Instalar dependencias con irispython

```bash
docker exec noshow-iris /usr/irissys/bin/irispython -m pip install \
  fastapi==0.115.0 httpx==0.27.0 anthropic==0.40.0 \
  python-dotenv==1.0.0 a2wsgi==1.10.4 flask
```

> `flask` es requerido aunque no se usa en la app: IRIS WSGI Experimental valida la presencia de un framework conocido al activar la Web App. Sin él, el portal muestra "Unable to find a WSGI framework" y no permite guardar.

### 8.4 Verificar que la app carga

```bash
docker exec noshow-iris /usr/irissys/bin/irispython -c "
import sys; sys.path.insert(0, '/opt/iris105-chat')
from wsgi import app; print('OK:', type(app))"
# → OK: <class 'a2wsgi.asgi.ASGIMiddleware'>
```

### 8.5 Crear Web Application en IRIS

En Management Portal: `Sistema → Gestión de seguridad → Aplicaciones Web → Nueva`

| Campo | Valor |
|---|---|
| NOMBRE | `/csp/mlchat` |
| NameSpace | `MLTEST` |
| Activar | `WSGI [Experimental]` |
| Nombre de aplicación | `wsgi` |
| Nombre invocable | `app` |
| Directorio de aplicaciones WSGI | `/opt/iris105-chat` |
| Métodos de autenticación | `Sin autenticar` ✓ |

### 8.6 Verificar chat

```bash
curl http://localhost:52773/csp/mlchat/health
# → {"status":"ok","model":"claude-sonnet-4-6"}

curl -X POST http://localhost:52773/csp/mlchat/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"¿cuántos pacientes hay?","history":[]}'
# → {"reply":"Hay 200 pacientes registrados...","history":[...]}
```

---

## Paso 9 — Smoke tests completos

```bash
# API REST
curl http://localhost:52773/csp/mltest/api/health
curl -H "Authorization: Bearer demo-readonly-token" \
     http://localhost:52773/csp/mltest/api/ml/stats/summary
curl -H "Authorization: Bearer demo-readonly-token" \
     "http://localhost:52773/csp/mltest/api/ml/analytics/top-noshow?by=specialty"

# Scoring
curl -X POST http://localhost:52773/csp/mltest/api/ml/noshow/score \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" \
  -d '{"appointmentId":"APPT-1"}'

# Chat
curl -X POST http://localhost:52773/csp/mlchat/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"¿qué especialidad tiene más inasistencias?","history":[]}'

# UI
# Abrir en navegador:
# http://localhost:52773/csp/mltest2/GCSP.Basic.cls
# http://localhost:52773/csp/mltest2/GCSP.Agenda.cls
# http://localhost:52773/csp/mlchat/
```

---

## Paso 10 — Exposición pública (opcional, Cloudflare Tunnel)

Ver `docs/custom_gpt_cloudflare_runbook.md` para el flujo completo.

Resumen:
```bash
# Instalar cloudflared
brew install cloudflared         # macOS
# apt install cloudflared        # Ubuntu

# Autenticar
cloudflared tunnel login

# Crear tunnel
cloudflared tunnel create iris105

# Configurar ~/.cloudflared/config.yml
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: <TUNNEL-UUID>
credentials-file: /root/.cloudflared/<TUNNEL-UUID>.json
ingress:
  - hostname: mi-iris.ejemplo.com
    service: http://localhost:52773
  - hostname: chat.mi-iris.ejemplo.com
    service: http://localhost:52773
  - service: http_status:404
EOF

# Crear registros DNS
cloudflared tunnel route dns <TUNNEL-UUID> mi-iris.ejemplo.com
cloudflared tunnel route dns <TUNNEL-UUID> chat.mi-iris.ejemplo.com

# Levantar tunnel
cloudflared tunnel run iris105
```

---

## Resumen de URLs resultantes

| Servicio | URL local | URL pública (si hay tunnel) |
|---|---|---|
| Management Portal | `http://localhost:52773/csp/sys/` | — |
| API REST | `http://localhost:52773/csp/mltest/api/` | `https://mi-iris.ejemplo.com/csp/mltest/api/` |
| UI Basic | `http://localhost:52773/csp/mltest2/GCSP.Basic.cls` | `https://mi-iris.ejemplo.com/csp/mltest2/GCSP.Basic.cls` |
| UI Agenda | `http://localhost:52773/csp/mltest2/GCSP.Agenda.cls` | `https://mi-iris.ejemplo.com/csp/mltest2/GCSP.Agenda.cls` |
| Chat app | `http://localhost:52773/csp/mlchat/` | `https://mi-iris.ejemplo.com/csp/mlchat/` (mismo tunnel, mismo puerto) |

---

## Actualizar la app después de cambios en el código

```bash
# Volver a copiar archivos modificados
docker cp iris105-chat/main.py      noshow-iris:/opt/iris105-chat/main.py
docker cp iris105-chat/iris_client.py noshow-iris:/opt/iris105-chat/iris_client.py
docker cp iris105-chat/static/index.html noshow-iris:/opt/iris105-chat/static/index.html

# IRIS recarga el módulo WSGI automáticamente en cada request (no requiere reinicio)
# Solo se necesita reiniciar si se agregan nuevas dependencias pip
```

Actualizar clases ObjectScript:
```bash
docker cp src/IRIS105/REST/NoShowService.cls noshow-iris:/tmp/NoShowService.cls
docker exec -i noshow-iris iris session IRIS -U MLTEST <<'EOF'
Do $system.OBJ.Load("/tmp/NoShowService.cls","ck")
Do $SYSTEM.SQL.Purge()
Halt
EOF
```

---

## Persistencia de datos entre reinicios

Por defecto el contenedor **no persiste datos** al reiniciarse. Para persistir:

```bash
docker run -d \
  --name noshow-iris \
  -p 52773:52773 \
  -p 1972:1972 \
  -v $(pwd)/iris-data:/usr/irissys/mgr \
  intersystemsdc/irishealth-ml-community:latest
```

Con volumen montado, la base de datos, el modelo entrenado y los globals sobreviven reinicios. Solo hay que volver a hacer los pasos 8 (chat) si el contenedor se recrea desde cero.
