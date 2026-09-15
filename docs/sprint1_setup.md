# Sprint 1 — Setup y primer import

Este documento guía los pasos mínimos para dejar listo el entorno IRIS y probar la importación/compilación de las clases del POC IRIS105.

Requisitos previos

- InterSystems IRIS 2024.1 instalado (o contenedor Docker con IRIS).
- Visual Studio Code con la extensión InterSystems ObjectScript (ver `.vscode/extensions.json`).
- Acceso al namespace `MLTEST` (si no existe, crear según pasos abajo).

1) Crear namespace `MLTEST` (opcional: con Docker)

Si usas un contenedor Docker llamado `iris` y `iris session` disponible:

```bash
# Crear namespace (desde consola IRIS)
iris session IRIS -U %SYS
Do ##class(%SYS.Namespace).Create("MLTEST","USER")
# Habilitar interoperability en el namespace si se usarán Producciones
Do ##class(%EnsembleMgr).EnableNamespace("MLTEST", 1)
Halt
```

2) Copiar/colocar fuentes en el contenedor o en disco compartido

Si tu flujo usa volúmenes en Docker, monta `src/` en `/opt/irisapp/iris/src/`.
Si no, usa `docker cp` para copiar los archivos `.cls` al contenedor y luego cargar.

3) Cargar y compilar clases

Desde una sesión IRIS (ir a namespace `MLTEST` o `%SYS` para compilar):

```objectscript
Do $system.OBJ.Load("/opt/irisapp/iris/src/IRIS105/Domain/Patient.cls","ck")
Do $system.OBJ.Compile("IRIS105.Patient","ck")
# Repetir para el resto de clases o compilar paquete
Do $system.OBJ.CompilePackage("IRIS105","ckr")
```

4) Crear esquema SQL / revisar mappings

- Si prefieres usar SQL directo, aplicar `sql/create_tables.sql`.
- Para IntegratedML, las clases `%Persistent` son la fuente natural.

5) Ejecutar generación de datos mock (esqueleto)

- Implementar `IRIS105.Util.MockData.Generate()` y llamar desde una sesión IRIS.

```objectscript
Do ##class(IRIS105.Util.MockData).Generate($$$NULL)
```

6) Crear y entrenar el modelo IntegratedML

- Ejecutar los scripts en `sql/integratedml_model.sql` desde SQL en namespace `MLTEST`.

7) Buenas prácticas y recomendaciones rápidas

- Mantener fuentes en `src/` y usar volúmenes Docker o ZPM para despliegues.
- No versionar datos ni bases en Git.
- Ejecutar `Do ##class(Ens.Director).UpdateProduction()` si cambia XData en una Production.

**Referencia de buenas prácticas**

Este repositorio incluye una guía consolidada de buenas prácticas para proyectos InterSystems IRIS: `BUENAS_PRACTICAS_IRIS_COMBINADAS.md` en la raíz del proyecto. Contiene:

- Convenciones de estructura de repositorio y nombres de clases.
- Flujo recomendado para compilación y despliegue (volúmenes Docker, `Do $system.OBJ.CompilePackage(...)`).
- Comandos útiles para desarrollo local, debugging y testing.

Sugerencia rápida: antes de ejecutar cargas masivas, compilar el paquete y hacer una corrida de prueba con pocos registros:

El código va por stdin: un argumento posicional se interpreta como nombre de
rutina y devuelve `<INVALID ARGUMENT>`.

```bash
# Compilar paquete (dentro del contenedor, namespace MLTEST donde vive IRIS105)
docker exec -i <contenedor> iris session IRIS -U MLTEST <<'EOF'
Do $system.OBJ.CompilePackage("IRIS105","ckr")
Halt
EOF

# Ejecutar generador en namespace MLTEST
docker exec -i <contenedor> iris session IRIS -U MLTEST <<'EOF'
Do ##class(IRIS105.Util.MockData).Generate()
Halt
EOF
```

8) Verificación rápida

- Desde SQL: `SELECT * FROM INFORMATION_SCHEMA.ML_MODELS;`
- Consultas de ejemplo: `sql/demo_queries.sql`

-- Fin sprint1_setup.md
