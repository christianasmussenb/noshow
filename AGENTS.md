# Reglas para agentes en este repo

## El código se carga siempre desde `src/`

Nunca compilar o modificar código directo contra la instancia IRIS y dejarlo solo ahí:
así fue como el módulo `MANTEN` (repo `manten`) terminó cuatro meses viviendo dentro de
un contenedor sin que ningún repo lo reflejara.

Todo cambio a las clases de `IRIS105` o `GCSP` se edita en `src/IRIS105/` y `src/GCSP/`
de este repo, se copia al contenedor con `docker cp`, y se compila con `iris session`
por stdin (ver `docs/docker-replication-guide.md` y `readme.md`). El contenedor es
descartable: si se borra, el estado que importa se reconstruye desde este repo.

```bash
docker cp src/IRIS105 <contenedor>:/tmp/IRIS105
docker cp src/GCSP    <contenedor>:/tmp/GCSP
docker exec -i <contenedor> iris session IRIS -U MLTEST <<'EOF'
Do $system.OBJ.LoadDir("/tmp/IRIS105","ckr")
Do $system.OBJ.LoadDir("/tmp/GCSP","ckr")
Halt
EOF
```

`iris105-chat/` (la app WSGI de chat) se actualiza igual: editar en el repo, `docker cp`
al contenedor. Nunca editar los archivos directamente dentro de `/opt/iris105-chat/`.

## Los datos se regeneran desde los scripts de poblado

No restaurar datos desde exports ni backups. El generador vive en el repo:

```bash
docker exec -i <contenedor> iris session IRIS -U MLTEST <<'EOF'
Do ##class(IRIS105.Util.MockData).Generate()
Halt
EOF
```

Un `docker rm` del contenedor no debe ser un evento que preocupe: los datos se
regeneran desde acá, no se restauran desde una copia externa.

## Nada de `.env` en git

`.env`, `.env.docker` y cualquier archivo con credenciales quedan fuera de git
(`.gitignore`). Se versiona solo el `.example` correspondiente, con placeholders.
Si un agente necesita agregar una variable de entorno nueva, la agrega al `.example`
con un valor de ejemplo, nunca al archivo real.
