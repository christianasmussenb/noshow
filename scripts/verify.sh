#!/usr/bin/env bash
# Arnés de verificación de noshow — HTC21-PLAN-PRUEBAS.md
#
# Uso:
#   ./scripts/verify.sh [L1|L2|L3|L4|L5|L6|L11|all]
#
# Salida: una línea por check —
#   PASS|<capa>|<check>|<observado>
#   FAIL|<capa>|<check>|<esperado>|<observado>
# Exit code 0 = todo verde, 1 = al menos un FAIL, 2 = uso incorrecto.
#
# Variables de entorno (todas con el default de producción del proyecto;
# para probar en el puerto temporal, exportar antes de invocar):
#   CONTAINER_NAME   (default: noshow-iris)
#   NAMESPACE        (default: MLTEST)
#   WEB_PORT         (default: 52773)
#   SUPERSERVER_PORT (default: 1972)
#   TOKEN            (default: demo-readonly-token)
#   ENV_FILE         (default: .env.docker)
#   OLD_WEB_PORT     (default: 52773) -- puerto del contenedor viejo (iris105)
#                    para L11. No incluida en "all": se corre aparte, a
#                    propósito, mientras iris105 conviva con noshow-iris.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CONTAINER_NAME="${CONTAINER_NAME:-noshow-iris}"
NAMESPACE="${NAMESPACE:-MLTEST}"
WEB_PORT="${WEB_PORT:-52773}"
SUPERSERVER_PORT="${SUPERSERVER_PORT:-1972}"
TOKEN="${TOKEN:-demo-readonly-token}"
OLD_CONTAINER="${OLD_CONTAINER:-iris105}"
OLD_WEB_PORT="${OLD_WEB_PORT:-52773}"
ENV_FILE="${ENV_FILE:-.env.docker}"
BASE="http://localhost:${WEB_PORT}/csp/mltest/api"

FAILED=0

pass() { printf 'PASS|%s|%s|%s\n' "$1" "$2" "$3"; }
fail() { printf 'FAIL|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; FAILED=1; }

# Ejecuta ObjectScript por stdin (heredoc), nunca como argumento de iris session.
run_os() {
  docker exec -i "${CONTAINER_NAME}" iris session IRIS -U "${NAMESPACE}"
}

sql_count() {
  # $1 = SQL de una sola fila con un COUNT(*). Devuelve el número o vacío si falla.
  local sql="$1"
  local out
  out="$(run_os <<EOF
Set r=##class(%SQL.Statement).%ExecDirect(,"${sql}")
Do r.%Next()
Write "COUNT=",r.%GetData(1),!
Halt
EOF
)"
  echo "${out}" | sed -n 's/^COUNT=\([0-9-]*\).*/\1/p' | tail -1
}

l1() {
  local cap=L1
  docker compose --env-file "${ENV_FILE}" up -d >/dev/null 2>&1
  local insp
  insp="$(docker inspect "${CONTAINER_NAME}" 2>/dev/null)"
  if [[ -z "${insp}" ]]; then
    fail "$cap" "contenedor-existe" "docker inspect ${CONTAINER_NAME} devuelve datos" "sin datos / contenedor no existe"
    return
  fi
  local status mem restart nets
  status="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}")"
  mem="$(docker inspect -f '{{.HostConfig.Memory}}' "${CONTAINER_NAME}")"
  restart="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "${CONTAINER_NAME}")"
  nets="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "${CONTAINER_NAME}")"

  [[ "${status}" == "running" ]] && pass "$cap" "estado" "running" || fail "$cap" "estado" "running" "${status}"
  [[ "${mem}" == "4294967296" ]] && pass "$cap" "mem_limit" "4294967296" || fail "$cap" "mem_limit" "4294967296" "${mem}"
  [[ "${restart}" == "unless-stopped" ]] && pass "$cap" "restart_policy" "unless-stopped" || fail "$cap" "restart_policy" "unless-stopped" "${restart}"
  [[ "${nets}" == *htc21-net* ]] && pass "$cap" "red" "incluye htc21-net" "${nets}" || fail "$cap" "red" "incluye htc21-net" "${nets}"

  local ports
  ports="$(docker port "${CONTAINER_NAME}" 2>/dev/null)"
  if echo "${ports}" | grep -q "52773/tcp -> 127.0.0.1:${WEB_PORT}"; then
    pass "$cap" "puerto_web" "127.0.0.1:${WEB_PORT}"
  else
    fail "$cap" "puerto_web" "127.0.0.1:${WEB_PORT}" "$(echo "${ports}" | tr '\n' ';')"
  fi
  if echo "${ports}" | grep -q "1972/tcp -> 127.0.0.1:${SUPERSERVER_PORT}"; then
    pass "$cap" "puerto_superserver" "127.0.0.1:${SUPERSERVER_PORT}"
  else
    fail "$cap" "puerto_superserver" "127.0.0.1:${SUPERSERVER_PORT}" "$(echo "${ports}" | tr '\n' ';')"
  fi
}

l2() {
  local cap=L2
  local table="IRIS105.Patient"
  local antes despues
  antes="$(sql_count "SELECT COUNT(*) FROM ${table}")"
  if [[ -z "${antes}" ]]; then
    fail "$cap" "conteo_antes" "un número" "vacío — ¿namespace ${NAMESPACE} sin datos cargados (correr L3 primero)?"
    return
  fi

  docker compose --env-file "${ENV_FILE}" down >/dev/null 2>&1
  docker compose --env-file "${ENV_FILE}" up -d >/dev/null 2>&1
  sleep 90

  despues="$(sql_count "SELECT COUNT(*) FROM ${table}")"
  if [[ -z "${despues}" ]]; then
    fail "$cap" "namespace_sobrevive" "namespace ${NAMESPACE} accesible tras down/up" "consulta falló — namespace no existe o durable %SYS no tomó"
    return
  fi
  if [[ "${antes}" == "${despues}" ]]; then
    pass "$cap" "persistencia_${table}" "ANTES=${antes} DESPUES=${despues}"
  else
    fail "$cap" "persistencia_${table}" "ANTES=DESPUES" "ANTES=${antes} DESPUES=${despues}"
  fi
}

l3() {
  local cap=L3
  local repo_count compiled_count
  repo_count="$(find "${REPO_ROOT}/src" -name '*.cls' | wc -l | tr -d ' ')"
  compiled_count="$(sql_count "SELECT COUNT(*) FROM %Dictionary.ClassDefinition WHERE System=0 AND (Name LIKE 'IRIS105.%' OR Name LIKE 'GCSP.%')")"
  if [[ "${repo_count}" == "${compiled_count}" ]]; then
    pass "$cap" "clases_compiladas" "${compiled_count} (repo=${repo_count})"
  else
    fail "$cap" "clases_compiladas" "${repo_count}" "${compiled_count}"
  fi

  local patients physicians appts
  patients="$(sql_count "SELECT COUNT(*) FROM IRIS105.Patient")"
  physicians="$(sql_count "SELECT COUNT(*) FROM IRIS105.Physician")"
  appts="$(sql_count "SELECT COUNT(*) FROM IRIS105.Appointment")"
  [[ "${patients}" == "100" ]] && pass "$cap" "pacientes" "100" || fail "$cap" "pacientes" "100" "${patients}"
  [[ "${physicians}" == "8" ]] && pass "$cap" "medicos" "8" || fail "$cap" "medicos" "8" "${physicians}"
  if [[ -n "${appts}" && "${appts}" -gt 0 ]] 2>/dev/null; then
    pass "$cap" "citas_generadas" "${appts} (>0)"
  else
    fail "$cap" "citas_generadas" ">0" "${appts:-vacío}"
  fi
}

curl_status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

l4() {
  local cap=L4
  local code

  code="$(curl_status "${BASE}/health")"
  [[ "${code}" == "200" ]] && pass "$cap" "GET /api/health" "200" || fail "$cap" "GET /api/health" "200" "${code}"

  code="$(curl_status -H "Authorization: Bearer ${TOKEN}" "${BASE}/ml/stats/summary")"
  [[ "${code}" == "200" ]] && pass "$cap" "GET /ml/stats/summary (con token)" "200" || fail "$cap" "GET /ml/stats/summary (con token)" "200" "${code}"

  code="$(curl_status "${BASE}/ml/stats/summary")"
  [[ "${code}" == "401" ]] && pass "$cap" "GET /ml/stats/summary (sin token)" "401" || fail "$cap" "GET /ml/stats/summary (sin token)" "401" "${code} — un 200 sin token es hallazgo de seguridad"

  code="$(curl_status -H "Authorization: Bearer ${TOKEN}" "${BASE}/ml/stats/model")"
  [[ "${code}" == "200" ]] && pass "$cap" "GET /ml/stats/model" "200" || fail "$cap" "GET /ml/stats/model" "200" "${code}"

  code="$(curl_status -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
    -d '{"features":{"PatientId":10,"PhysicianId":"PHY-3","BoxId":"BOX-2","SpecialtyId":"SPEC-1","StartDateTime":"2025-11-18 10:30:00","BookingChannel":"WEB","BookingDaysInAdvance":5,"HasSMSReminder":1,"Reason":"Control"}}' \
    "${BASE}/ml/noshow/score")"
  [[ "${code}" == "200" ]] && pass "$cap" "POST /ml/noshow/score (adhoc)" "200" || fail "$cap" "POST /ml/noshow/score (adhoc)" "200" "${code}"

  code="$(curl_status -H "Authorization: Bearer ${TOKEN}" "${BASE}/ml/analytics/top-specialties")"
  [[ "${code}" == "200" ]] && pass "$cap" "GET /ml/analytics/top-specialties" "200" || fail "$cap" "GET /ml/analytics/top-specialties" "200" "${code}"

  code="$(curl_status -H "Authorization: Bearer ${TOKEN}" "${BASE}/ml/appointments/active")"
  [[ "${code}" == "200" ]] && pass "$cap" "GET /ml/appointments/active" "200" || fail "$cap" "GET /ml/appointments/active" "200" "${code}"
}

check_page() {
  local cap="$1" check="$2" url="$3" marker="$4"
  local body code
  body="$(curl -s -w '\n%{http_code}' "${url}")"
  code="$(echo "${body}" | tail -1)"
  body="$(echo "${body}" | sed '$d')"
  if [[ "${code}" != "200" ]]; then
    fail "$cap" "$check" "200" "${code}"
    return
  fi
  if echo "${body}" | grep -qF "${marker}"; then
    pass "$cap" "$check" "200 + marcador '${marker}'"
  else
    fail "$cap" "$check" "200 + marcador '${marker}'" "200 sin el marcador"
  fi
}

l5() {
  local cap=L5
  check_page "$cap" "GCSP.Basic (UI operaciones)" "http://localhost:${WEB_PORT}/csp/mltest2/GCSP.Basic.cls" "NoShowModel2"
  check_page "$cap" "GCSP.Agenda (agenda semanal)" "http://localhost:${WEB_PORT}/csp/mltest2/GCSP.Agenda.cls" "Agenda de pacientes"
  check_page "$cap" "mlchat (index)" "http://localhost:${WEB_PORT}/csp/mlchat/" "Asistente de Agenda"

  local code
  code="$(curl_status "http://localhost:${WEB_PORT}/csp/mlchat/health")"
  [[ "${code}" == "200" ]] && pass "$cap" "mlchat /health" "200" || fail "$cap" "mlchat /health" "200" "${code}"
}

l6() {
  local cap=L6

  local model_resp
  model_resp="$(curl -s -H "Authorization: Bearer ${TOKEN}" "${BASE}/ml/stats/model")"
  if echo "${model_resp}" | grep -q '"defaultTrainedModel"[[:space:]]*:[[:space:]]*"[^"]\+"'; then
    pass "$cap" "modelo_entrenado" "defaultTrainedModel presente en /ml/stats/model"
  else
    fail "$cap" "modelo_entrenado" "defaultTrainedModel no vacío" "${model_resp}"
    return
  fi

  local active_resp appt_id
  active_resp="$(curl -s -H "Authorization: Bearer ${TOKEN}" "${BASE}/ml/appointments/active")"
  appt_id="$(echo "${active_resp}" | grep -o '"appointmentId"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:"([^"]*)"/\1/')"
  if [[ -z "${appt_id}" ]]; then
    fail "$cap" "score_cita_real" "una cita activa para scorear" "sin citas en /ml/appointments/active"
    return
  fi

  local score_resp prob
  score_resp="$(curl -s -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
    -d "{\"appointmentId\":\"${appt_id}\"}" "${BASE}/ml/noshow/score")"
  prob="$(echo "${score_resp}" | grep -o '"noShowProb"[[:space:]]*:[[:space:]]*[0-9.]*' | head -1 | sed -E 's/.*:[[:space:]]*//')"
  if [[ -n "${prob}" ]] && awk -v p="${prob}" 'BEGIN{exit !(p>=0 && p<=1)}'; then
    pass "$cap" "score_cita_real" "appointmentId=${appt_id} noShowProb=${prob} (rango válido)"
  else
    fail "$cap" "score_cita_real" "noShowProb en [0,1]" "${score_resp}"
  fi
}

l11() {
  # Regresión: mismo endpoint contra el contenedor nuevo (WEB_PORT) y el
  # viejo en vivo (OLD_CONTAINER/OLD_WEB_PORT), comparando código de estado
  # y forma general del payload (no byte-a-byte). No la corre "all": es una
  # capa de migración, tiene sentido solo mientras conviven ambos
  # contenedores.
  local cap=L11
  local old_base="http://localhost:${OLD_WEB_PORT}/csp/mltest/api"

  compare_endpoint() {
    local check="$1" path="$2" auth="$3"
    local new_code old_code new_body old_body
    if [[ "${auth}" == "auth" ]]; then
      new_code="$(curl -s -o /tmp/l11_new.json -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "${BASE}${path}")"
      old_code="$(curl -s -o /tmp/l11_old.json -w '%{http_code}' -H "Authorization: Bearer ${TOKEN}" "${old_base}${path}")"
    else
      new_code="$(curl -s -o /tmp/l11_new.json -w '%{http_code}' "${BASE}${path}")"
      old_code="$(curl -s -o /tmp/l11_old.json -w '%{http_code}' "${old_base}${path}")"
    fi
    new_body="$(cat /tmp/l11_new.json 2>/dev/null)"
    old_body="$(cat /tmp/l11_old.json 2>/dev/null)"
    rm -f /tmp/l11_new.json /tmp/l11_old.json

    if [[ "${new_code}" != "${old_code}" ]]; then
      fail "$cap" "${check}" "mismo código de estado (viejo=${old_code})" "nuevo=${new_code}"
      return
    fi
    # Forma general: mismas claves de primer nivel del JSON, no valores exactos.
    local new_keys old_keys
    new_keys="$(echo "${new_body}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sorted(d.keys()) if isinstance(d,dict) else 'not-a-dict')" 2>/dev/null)"
    old_keys="$(echo "${old_body}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sorted(d.keys()) if isinstance(d,dict) else 'not-a-dict')" 2>/dev/null)"
    if [[ -z "${new_keys}" || -z "${old_keys}" ]]; then
      pass "$cap" "${check}" "mismo código (${new_code}), payload no-JSON en ambos"
    elif [[ "${new_keys}" == "${old_keys}" ]]; then
      pass "$cap" "${check}" "mismo código (${new_code}) y misma forma de payload"
    else
      fail "$cap" "${check}" "mismas claves de payload (viejo=${old_keys})" "nuevo=${new_keys}"
    fi
  }

  compare_endpoint "GET /api/health" "/health" noauth
  compare_endpoint "GET /ml/stats/summary" "/ml/stats/summary" auth
  compare_endpoint "GET /ml/stats/model" "/ml/stats/model" auth
  compare_endpoint "GET /ml/analytics/top-specialties" "/ml/analytics/top-specialties" auth
  compare_endpoint "GET /ml/appointments/active" "/ml/appointments/active" auth
}

case "${1:-all}" in
  L1) l1 ;;
  L2) l2 ;;
  L3) l3 ;;
  L4) l4 ;;
  L5) l5 ;;
  L6) l6 ;;
  L11) l11 ;;
  all) l1; l2; l3; l4; l5; l6 ;;
  *) echo "uso: $0 [L1|L2|L3|L4|L5|L6|L11|all]" >&2; exit 2 ;;
esac

exit "${FAILED}"
