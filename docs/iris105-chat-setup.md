# iris105-chat — Guía de instalación y operación

> **Desde `docker-compose.yml` + `docker/Dockerfile`, la instalación es automática.**
> `docker compose up -d --build` construye la imagen con las dependencias del chat
> (`iris105-chat/requirements.txt`) y `IRIS105.Util.WebAppSetup.ConfigureAll()` registra
> `/csp/mlchat` junto con `/csp/mltest` y `/csp/mltest2`. Ver `readme.md`. Las secciones 1-6
> de abajo describen ese mismo proceso paso a paso, útil para depurar o para instalar sobre
> un contenedor que no usa este compose; no son necesarias en el flujo normal.

App web de chat en lenguaje natural sobre los datos de IRIS105.  
El usuario escribe preguntas en español; Claude (Anthropic SDK) orquesta llamadas a la API REST de IRIS y devuelve respuestas interpretadas.

---

## Arquitectura

```
Navegador
    │  GET /csp/mlchat/          (sirve index.html)
    │  POST /csp/mlchat/chat     (loop tool_use → IRIS)
    ▼
IRIS Web Gateway  (WSGI Experimental)
    ├── wsgi.py  →  ASGIMiddleware(FastAPI app)
    ├── main.py  →  endpoint /chat con loop Claude tool_use
    ├── iris_client.py  →  12 tools → IRIS REST API localhost:52773
    ├── tools.py  →  definiciones de tools para Claude
    ├── system_prompt.py  →  contexto del dominio en español
    └── static/index.html  →  chat UI vanilla JS
              │
              │ http://localhost:52773/csp/mltest  (interno, sin CORS)
              ▼
         IRIS REST API  (IRIS105.REST.NoShowService)
```

**Por qué WSGI dentro de IRIS y no un servicio separado**:  
Elimina la necesidad de un segundo contenedor, un puerto extra en Cloudflare y gestión de CORS. Todo corre dentro del proceso web de IRIS.

---

## Estructura de archivos

```
iris105-chat/
├── wsgi.py            ← entry point para IRIS WSGI (ASGIMiddleware wrapper)
├── main.py            ← FastAPI: GET /, GET /health, POST /chat
├── iris_client.py     ← dispatcher de las 12 tools hacia IRIS REST
├── tools.py           ← definiciones de tools para Claude API
├── system_prompt.py   ← contexto del dominio (especialidades, horarios, etc.)
├── requirements.txt   ← dependencias Python
├── Dockerfile         ← para despliegue standalone (alternativa a WSGI)
├── .env               ← secrets (NO versionar — está en .gitignore)
├── .env.example       ← template sin secrets (versionar)
└── static/
    └── index.html     ← chat UI (vanilla JS, sin frameworks)
```

---

## Dependencias Python

```
fastapi==0.115.0
uvicorn==0.30.0       # solo para modo standalone/dev
httpx==0.27.0
anthropic==0.40.0
python-dotenv==1.0.0
a2wsgi==1.10.4        # adaptador ASGI→WSGI para IRIS Web Gateway
```

**Nota**: FastAPI es ASGI (async). IRIS Web Gateway solo acepta WSGI (sync).  
`a2wsgi.ASGIMiddleware` adapta la app FastAPI para ser invocada como WSGI.

---

## Variables de entorno (`.env`)

```
ANTHROPIC_API_KEY=sk-ant-...      # clave Anthropic
IRIS_BASE_URL=http://localhost:52773/csp/mltest
IRIS_TOKEN=demo-readonly-token
```

En producción Docker usar el nombre del servicio: `IRIS_BASE_URL=http://iris:52773/csp/mltest`

**Cómo se carga el `.env` dentro de IRIS WSGI**:  
`load_dotenv()` sin argumento busca el `.env` en el working directory del proceso, que dentro de IRIS no es el directorio de la app. Por eso se usa path absoluto relativo al módulo:

```python
from pathlib import Path
load_dotenv(Path(__file__).parent / ".env")
```

Este mismo patrón aplica a `StaticFiles` y `FileResponse` — rutas relativas fallan bajo IRIS WSGI:

```python
_BASE_DIR = Path(__file__).parent
app.mount("/static", StaticFiles(directory=str(_BASE_DIR / "static")))
return FileResponse(str(_BASE_DIR / "static" / "index.html"))
```

---

## Instalación dentro del contenedor Docker de IRIS

### 1. Copiar archivos al contenedor

```bash
docker cp iris105-chat <nombre-contenedor>:/opt/iris105-chat
```

### 2. Crear el `.env` dentro del contenedor

> `docker exec bash -c 'cat > ...'` falla con **Permission denied** si el directorio pertenece al usuario 501 del host (caso típico con `docker cp` desde Mac). Usar `docker cp` desde el host en su lugar:

```bash
cat > /tmp/iris105-chat.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-...tu-key...
IRIS_BASE_URL=http://localhost:52773/csp/mltest
IRIS_TOKEN=demo-readonly-token
EOF
docker cp /tmp/iris105-chat.env <nombre-contenedor>:/opt/iris105-chat/.env
rm /tmp/iris105-chat.env
```

### 3. Instalar dependencias con irispython

```bash
docker exec <nombre-contenedor> /usr/irissys/bin/irispython -m pip install \
  fastapi==0.115.0 httpx==0.27.0 anthropic==0.40.0 \
  python-dotenv==1.0.0 a2wsgi==1.10.4 flask
```

> - No instalar `uvicorn` — no se usa en modo WSGI de IRIS.
> - `flask` es requerido aunque no se usa directamente: IRIS WSGI Experimental valida la presencia de un framework conocido (flask o django) al configurar la Web App. Sin él, el portal muestra "Unable to find a WSGI framework".

### 4. Verificar que la app carga

```bash
docker exec <nombre-contenedor> /usr/irissys/bin/irispython -c "
import sys
sys.path.insert(0, '/opt/iris105-chat')
from wsgi import app
print('OK:', type(app))
"
```

Resultado esperado: `OK: <class 'a2wsgi.asgi.ASGIMiddleware'>`

### 5. Configurar Web Application en IRIS Management Portal

`Sistema → Gestión de seguridad → Aplicaciones Web → Nueva aplicación`

| Campo | Valor |
|---|---|
| NOMBRE | `/csp/mlchat` |
| NameSpace | `MLTEST` |
| Activar | `WSGI [Experimental]` |
| Nombre de aplicación | `wsgi` |
| Nombre invocable | `app` |
| Directorio de aplicaciones WSGI | `/opt/iris105-chat` |
| Métodos de autenticación | `Sin autenticar` ✓ |

### 6. Verificar

```bash
curl http://localhost:52773/csp/mlchat/health
# → {"status":"ok","model":"claude-sonnet-4-6"}

curl http://localhost:52773/csp/mlchat/
# → HTML del chat
```

---

## Modo standalone (desarrollo local sin IRIS WSGI)

```bash
cd iris105-chat
pip install -r requirements.txt
uvicorn main:app --port 8000 --reload
```

- UI: `http://localhost:8000`
- En el `.env` usar `IRIS_BASE_URL=http://localhost:52773/csp/mltest`

---

## Modo Docker standalone (alternativa sin WSGI)

```bash
cd iris105-chat
docker build -t iris105-chat .
docker run -d \
  --name iris105-chat \
  --network host \
  --env-file .env \
  --restart unless-stopped \
  iris105-chat
```

`--network host` permite que `localhost:52773` dentro del contenedor alcance al IRIS del host.

---

## Exposición pública con Cloudflare Tunnel

Agregar entrada en `~/.cloudflared/config.yml` antes del `http_status:404`:

```yaml
ingress:
  - hostname: iris105m4.htc21.site
    service: http://localhost:52773
  - hostname: chat.iris105m4.htc21.site
    service: http://localhost:52773    # WSGI: el chat va por el mismo puerto de IRIS
  - service: http_status:404
```

> Si el chat corre como standalone Docker en el puerto 8000, usar `service: http://localhost:8000`.

Crear registro DNS:
```bash
cloudflared tunnel route dns <TUNNEL-UUID> chat.iris105m4.htc21.site
sudo systemctl restart cloudflared
```

---

## Tools disponibles (12)

| Tool | Método | Endpoint IRIS |
|---|---|---|
| `health_check` | GET | `/api/health` |
| `stats_summary` | GET | `/api/ml/stats/summary` |
| `model_details` | GET | `/api/ml/stats/model` |
| `top_noshow` | GET | `/api/ml/analytics/top-noshow` |
| `top_specialties` | GET | `/api/ml/analytics/top-specialties` |
| `top_physicians` | GET | `/api/ml/analytics/top-physicians` |
| `busiest_day` | GET | `/api/ml/analytics/busiest-day` |
| `occupancy_weekly` | GET | `/api/ml/analytics/occupancy-weekly` |
| `occupancy_trend` | GET | `/api/ml/analytics/occupancy-trend` |
| `scheduled_patients` | GET | `/api/ml/analytics/scheduled-patients` |
| `active_appointments` | GET | `/api/ml/appointments/active` |
| `score_noshow` | POST | `/api/ml/noshow/score` |

Excluidas intencionalmente: `generate_mock_data`, `capacity_config` (operaciones mutables).

---

## Aprendizajes clave (troubleshooting)

| Problema | Causa | Solución |
|---|---|---|
| `404` al enviar mensaje desde UI | `fetch('/chat')` usa path absoluto | Usar `window.location.pathname.replace(/\/[^/]*$/, '') + '/chat'` |
| `load_dotenv()` no encuentra `.env` | Working dir de IRIS ≠ directorio de la app | `load_dotenv(Path(__file__).parent / ".env")` |
| `RuntimeError: Directory 'static' does not exist` | `StaticFiles("static")` usa path relativo | `StaticFiles(directory=str(Path(__file__).parent / "static"))` |
| Variables de entorno vacías en `iris_client.py` | Las constantes de módulo se evalúan antes de `load_dotenv()` en main.py | Llamar `load_dotenv()` al inicio de `iris_client.py` también |
| `MockValSer` / error de serialización Pydantic | `response.content` del SDK Anthropic contiene objetos no-dict | Convertir con `block.model_dump()` antes de devolver al cliente |
| App no carga en IRIS WSGI | FastAPI es ASGI, no WSGI | Usar `a2wsgi.ASGIMiddleware(app)` como callable en `wsgi.py` |
| "Unable to find a WSGI framework" en Management Portal | IRIS verifica presencia de flask o django antes de activar WSGI | `irispython -m pip install flask` (no se usa en la app, solo satisface el check) |
| `Permission denied` al crear `.env` con `docker exec bash -c` | Directorio copiado con `docker cp` desde Mac pertenece al uid 501 del host, no a `irisowner` | Crear `.env` en el host y copiarlo con `docker cp` |
