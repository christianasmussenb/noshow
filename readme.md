# IRIS105 — POC predicción de No-Show con IntegratedML + Chat en lenguaje natural

POC que combina InterSystems IRIS Community 2026.1, IntegratedML y una app de chat con Claude (Anthropic) para analizar y predecir inasistencias a citas médicas en lenguaje natural.

**Namespace**: `MLTEST` · **Imagen Docker**: `intersystemsdc/irishealth-ml-community:2026.1`

---

## Qué hay en este proyecto

| Componente | Descripción | URL |
|---|---|---|
| API REST | 15 endpoints de scoring, analytics y configuración | `/csp/mltest/api/` |
| UI Basic | Operaciones generales, entrenamiento ML paso a paso | `/csp/mltest2/GCSP.Basic.cls` |
| UI Agenda | Agenda visual semanal/mensual con riesgo de no-show | `/csp/mltest2/GCSP.Agenda.cls` |
| Chat app | Preguntas en español respondidas con datos reales de IRIS | `/csp/mlchat/` |

---

## Inicio rápido (Docker)

Ver la guía completa en `docs/docker-replication-guide.md`. Resumen:

```bash
# 1. Levantar IRIS
docker run -d --name iris105 -p 52773:52773 -p 1972:1972 \
  intersystemsdc/irishealth-ml-community:latest

# 2. Crear namespace y compilar
docker exec iris105 iris session IRIS -U '%SYS' \
  'Do ##class(%SYS.Namespace).Create("MLTEST","USER") Halt'
docker cp src/IRIS105 iris105:/tmp/IRIS105
docker cp src/GCSP    iris105:/tmp/GCSP
docker exec iris105 iris session IRIS -U MLTEST \
  'Do $system.OBJ.LoadDir("/tmp/IRIS105","ckr") Do $system.OBJ.LoadDir("/tmp/GCSP","ckr") Halt'

# 3. Configurar web apps y token
docker exec iris105 iris session IRIS -U MLTEST \
  'Do ##class(IRIS105.Util.WebAppSetup).ConfigureAll() Do ##class(IRIS105.Util.ProjectSetup).Init() Halt'

# 4. Generar datos y entrenar modelo
docker exec iris105 iris session IRIS -U MLTEST \
  'Do ##class(IRIS105.Util.MockData).Generate() Halt'
# Luego entrenar via UI o API (ver docs/docker-replication-guide.md paso 7)

# 5. Instalar chat app
docker cp iris105-chat iris105:/opt/iris105-chat
docker exec iris105 /usr/irissys/bin/irispython -m pip install \
  fastapi==0.115.0 httpx==0.27.0 anthropic==0.40.0 python-dotenv==1.0.0 a2wsgi==1.10.4
# Crear /opt/iris105-chat/.env con ANTHROPIC_API_KEY, IRIS_BASE_URL, IRIS_TOKEN
# Configurar web app /csp/mlchat en Management Portal (ver docs/iris105-chat-setup.md)
```

---

## Estado del proyecto

- ✅ Clases persistentes: Patient, Physician, Box, Specialty, Appointment, AppointmentRisk
- ✅ Generador mock con restricciones horarias y tasas NoShow configurables por especialidad
- ✅ API REST completa (15 endpoints) con autenticación Bearer token
- ✅ Modelo IntegratedML `NoShowModel2` con scoring y persistencia de resultados
- ✅ UI CSP: Basic (operaciones, entrenamiento guiado) + Agenda (visual con riesgo ML)
- ✅ Chat app Python (FastAPI + Claude tool_use) deployada como WSGI en IRIS
- ✅ OpenAPI 3.1.0 documentado (`docs/openapi.yaml`) para Custom GPT
- ✅ Cloudflare Tunnel para acceso público (`iris105m4.htc21.site`)
- ⏳ Configurar subdominio `chat.iris105m4.htc21.site` para el chat
- ⏳ Capacidad realista persistente por box/especialidad
- ⏳ Índices compuestos en Appointment para analytics
- ⏳ Tests automatizados

---

## API REST (base: `/csp/mltest`)

Todos los endpoints requieren `Authorization: Bearer <token>` excepto `/api/health`.

```bash
# Token de demo (inicializado por ProjectSetup.Init)
# Bearer demo-readonly-token

# Health check
curl http://localhost:52773/csp/mltest/api/health

# Resumen general
curl -H "Authorization: Bearer demo-readonly-token" \
     http://localhost:52773/csp/mltest/api/ml/stats/summary

# Score por appointmentId
curl -X POST http://localhost:52773/csp/mltest/api/ml/noshow/score \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" \
  -d '{"appointmentId":"APPT-1"}'

# Score adhoc
curl -X POST http://localhost:52773/csp/mltest/api/ml/noshow/score \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" \
  -d '{"features":{"PatientId":10,"PhysicianId":"PHY-3","BoxId":"BOX-2","SpecialtyId":"SPEC-1",
       "StartDateTime":"2025-11-18 10:30:00","BookingChannel":"WEB",
       "BookingDaysInAdvance":5,"HasSMSReminder":1,"Reason":"Control"}}'

# Analytics
curl -H "Authorization: Bearer demo-readonly-token" \
     "http://localhost:52773/csp/mltest/api/ml/analytics/top-noshow?by=specialty&limit=3"

# Generar mock adicional
curl -X POST http://localhost:52773/csp/mltest/api/ml/mock/generate \
  -H "Authorization: Bearer demo-readonly-token" \
  -H "Content-Type: application/json" \
  -d '{"months":3,"targetOccupancy":0.85,"patients":200,"clearBeforeGenerate":1,
       "specialtyNoShowRates":{"SPEC-1":0.12,"SPEC-2":0.20,"SPEC-3":0.08}}'
```

### Endpoints disponibles

| Grupo | Endpoint |
|---|---|
| Scoring | `POST /api/ml/noshow/score` |
| Stats | `GET /api/ml/stats/summary`, `GET /api/ml/stats/model`, `GET /api/ml/stats/lastAppointmentByPatient` |
| Analytics | `GET /api/ml/analytics/busiest-day`, `top-specialties`, `top-physicians`, `top-noshow`, `occupancy-weekly`, `scheduled-patients`, `occupancy-trend` |
| Appointments | `GET /api/ml/appointments/active` |
| Config | `GET|POST /api/ml/config/capacity` |
| Modelo | `POST /api/ml/model/step/execute` (steps 1-6, excluido del Custom GPT) |
| Mock | `POST /api/ml/mock/generate` |
| Health | `GET /api/health` |

---

## Chat app (`/csp/mlchat/`)

App web en lenguaje natural. El usuario escribe preguntas en español; Claude llama las tools necesarias y devuelve respuestas interpretadas con tablas y formato.

```bash
# Health
curl http://localhost:52773/csp/mlchat/health

# Pregunta directa
curl -X POST http://localhost:52773/csp/mlchat/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"¿qué especialidad tiene más inasistencias?","history":[]}'
```

Ver `docs/iris105-chat-setup.md` para instalación detallada.

---

## Autenticación

- Validación contra global: `^IRIS105("API","Tokens",token)`
- Agregar token: `Set ^IRIS105("API","Tokens","mi-token")=1`
- Token de demo inicializado por `ProjectSetup.Init()`: `demo-readonly-token`

---

## Notas de compatibilidad IRIS 2024.1

- `INFORMATION_SCHEMA.ML_MODELS`: usar `CREATE_TIMESTAMP` (no `STATUS`); columnas `PREDICTING_COLUMN_NAME`, `WITH_COLUMNS`
- `TOP ?` parametrizado no soportado: concatenar el límite en el SQL
- Después de cambios de clase: `Do $system.OBJ.Compile("...","ck")` + `Do $SYSTEM.SQL.Purge()`
- Web app CSP `/csp/mltest2`: debe tener `DispatchClass` vacío para servir múltiples `.cls` por ruta

---

## Documentación relacionada

| Documento | Contenido |
|---|---|
| `docs/docker-replication-guide.md` | **Guía completa para replicar en otro IRIS desde cero** |
| `docs/iris105-chat-setup.md` | Instalación y configuración detallada del chat app |
| `docs/arquitectura.md` | Visión funcional y diagrama de componentes |
| `docs/custom_gpt_cloudflare_runbook.md` | Despliegue con Cloudflare Tunnel + Custom GPT |
| `docs/openapi.yaml` | Especificación OpenAPI 3.1.0 completa |
| `docs/demo_script.md` | Guion rápido de demo (SQL + cURL) |
| `docs/sprint_status.md` | Historial de avances y pendientes |
| `docs/iris105-upgrade-runbook.md` | Estado operativo, recreación y aprendizajes del upgrade |
| `BUENAS_PRACTICAS_IRIS_COMBINADAS.md` | Guía de buenas prácticas para proyectos IRIS |

---

## Scripts útiles

```bash
# Compilar paquete completo
./scripts/compile_package.sh iris105 MLTEST

# Actualizar chat app en el contenedor
docker cp iris105-chat/main.py       iris105:/opt/iris105-chat/main.py
docker cp iris105-chat/static/index.html iris105:/opt/iris105-chat/static/index.html

# Ver logs del chat (desde IRIS WSGI, los errores van al log de IRIS)
docker exec iris105 cat /usr/irissys/mgr/MLTEST/IRIS.log | tail -30
```
