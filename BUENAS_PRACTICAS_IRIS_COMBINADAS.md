# Buenas prácticas para proyectos InterSystems IRIS + ObjectScript

Estado: versión consolidada que incluye extractos textuales desde iris102.  
Propósito: plantilla reutilizable para iniciar proyectos IRIS + ObjectScript con buenas prácticas, ejemplos operativos y una hoja de referencia rápida de ObjectScript.

---

## Índice
- 1. Alcance y objetivos
- 2. Requisitos y herramientas recomendadas
- 3. Estructura recomendada del repositorio
- 4. Git & packaging
- 5. Desarrollo local y CI
- 6. Convenciones de código ObjectScript
- 7. Transacciones y concurrencia
- 8. Acceso a datos y performance
- 9. REST / FHIR / Integraciones
- 10. Testing
- 11. Debugging y diagnóstico
- 12. Seguridad y configuración
- 13. Operación y despliegue
- 14. Recursos y enlaces útiles
- 15. Contenidos insertados desde iris102
  - A. @BUENAS_PRACTICAS_IRIS.md (insertado)
  - B. @objectscript-cheat-sheet.md (insertado)

---

## 1. Alcance y objetivos
- Establecer estructura de repositorio, convenciones de código y flujo de trabajo reproducible.
- Facilitar desarrollo local con Docker, despliegues controlados (ZPM / paquetes) y CI.
- Mantener código legible, modular y testeable en ObjectScript y componentes IRIS (clases persistentes, rutinas, servicios REST/ENS, colas).

## 2. Requisitos y herramientas recomendadas
- InterSystems IRIS (documentar versión objetivo).
- VS Code con extensión "InterSystems ObjectScript".
- ZPM para empaquetado y despliegue.
- Docker / docker-compose para entornos reproducibles.
- Git + GitHub y workflows CI.
- Postman / Insomnia para APIs; herramientas FHIR si aplica.

## 3. Estructura recomendada del repositorio
- /src
  - /src/classes
  - /src/routines
  - /src/sql
  - /src/web (si aplica)
- /deploy
- /docker
- /tests
- /docs
- /scripts
- .vscode
- runtime.config.json, env.example

(Adaptar convenciones a tu equipo.)

## 4. Git & packaging
- Versionar solo código y configuraciones exportables.
- Ignorar datos y bases IRIS en .gitignore.
- Empaquetar con ZPM; usar tags semánticos.
- Mantener CHANGELOG y README.

## 5. Desarrollo local y CI
- docker-compose con namespace precreado e import automático de fuentes.
- Scripts rebuild/import para facilitar desarrollo local.
- CI que arranque un contenedor IRIS, importe fuentes/paquete y ejecute tests.

## 6. Convenciones de código ObjectScript
- Nombres de clases siguiendo namespaces (MiOrg.Component.Clase).
- Metodología: separar acceso a datos de lógica de negocio.
- Manejo de errores con excepciones (%Exception) y logging estructurado.
- Evitar uso indiscriminado de globals; preferir %Persistent.

## 7. Transacciones y concurrencia
- Uso controlado de transacciones; evitar bloqueos largos.
- Jobs/asíncrono para procesos background.

## 8. Acceso a datos y performance
- Clases persistentes para datos estructurados.
- Indices en campos de filtro y joins.
- Operaciones bulk para masivos.

## 9. REST / FHIR / Integraciones
- Usar adaptadores nativos de IRIS para REST.
- En FHIR, respetar versiones y validaciones; incluir autenticación (OAuth2).
- Documentar endpoints y proveer colección Postman.

## 10. Testing (unitario e integración)
- Tests unitarios para lógica; tests de integración contra contenedor IRIS.
- Ejecutar tests en CI; mantener fixtures reproducibles.

## 11. Debugging y diagnóstico
- Uso de Management Portal, trace utilities y logging con request-id.
- Scripts para rebuild/import reproducible.

## 12. Seguridad y configuración
- No versionar secretos; usar vault/CI secrets/.env local.
- Configurar TLS en producción; revisar permisos de namespaces.

## 13. Operación y despliegue
- Documentar backups/restore y plan de rollback.
- Automatizar despliegues con ZPM o scripts; documentar pasos manuales.

## 14. Recursos y enlaces útiles
- Documentación oficial InterSystems IRIS (por versión).
- Guía ZPM, extensión ObjectScript para VS Code, recursos FHIR.
- Enlaces a los archivos fuente originales:
  - @BUENAS_PRACTICAS_IRIS.md: https://github.com/christianasmussenb/iris102/blob/main/@BUENAS_PRACTICAS_IRIS.md
  - @objectscript-cheat-sheet.md: https://github.com/christianasmussenb/iris102/blob/main/@objectscript-cheat-sheet.md

---

## 15. Contenidos insertados desde iris102

### A) Contenido completo de @BUENAS_PRACTICAS_IRIS.md (insertado)

# Buenas Prácticas para Desarrollo en InterSystems IRIS

## Guía de Desarrollo Basada en Experiencia del Proyecto iris102

**Fecha:** 17 de octubre de 2025  
**Proyecto Base:** iris102 - Integración CSV a MySQL/PostgreSQL vía ODBC  
**Autor:** Documentación basada en experiencia real de desarrollo

---

## 📋 Índice

1. [Estructura de Proyecto](#estructura-de-proyecto)
2. [Gestión de Código Fuente](#gestión-de-código-fuente)
3. [Compilación y Despliegue](#compilación-y-despliegue)
4. [Conectividad de Bases de Datos](#conectividad-de-bases-de-datos)
5. [Arquitectura de Interoperability](#arquitectura-de-interoperability)
6. [Debugging y Troubleshooting](#debugging-y-troubleshooting)
7. [Docker y Entorno de Desarrollo](#docker-y-entorno-de-desarrollo)
8. [Testing y Validación](#testing-y-validación)
9. [Errores Comunes y Soluciones](#errores-comunes-y-soluciones)

---

## 1. Estructura de Proyecto

### 1.1 Organización Recomendada de Directorios

proyecto-iris/
├── iris/
│   ├── Dockerfile                    # Construcción del contenedor IRIS
│   ├── Installer.cls                 # Clase de instalación/setup
│   ├── iris.script                   # Script de inicialización
│   ├── src/
│   │   └── <namespace>/              # Código fuente por namespace
│   │       └── prod/                 # Clases de producción
│   │           ├── *.cls             # Clases de negocio
│   │           └── Msg/              # Clases de mensajes
│   └── odbc/                         # Configuración ODBC si aplica
│       ├── odbc.ini
│       └── odbcinst.ini
├── data/
│   ├── IN/                           # Entrada de datos
│   ├── OUT/                          # Salida procesada
│   ├── LOG/                          # Logs de procesamiento
│   └── WIP/                          # Work in progress
├── sql/                              # Scripts SQL externos
│   ├── mysql_init.sql
│   └── postgres_init.sql
├── docker-compose.yml                # Orquestación de servicios
└── README.md                         # Documentación principal

### 1.2 Convenciones de Nombres

**Packages (Namespaces):**
- Usar PascalCase: `Demo`, `MyApp`, `CompanyName`
- Evitar guiones bajos o caracteres especiales

**Clases:**
- Business Services: `<Nombre>Service` → `Demo.FileService`
- Business Processes: `<Nombre>Process` → `Demo.Process`
- Business Operations: `<Nombre>Operation` → `Demo.MySQL.Operation`
- Messages: `Demo.Msg.<TipoMensaje>` → `Demo.Msg.FileProcessRequest`

**Properties:**
- PascalCase: `TargetConfigName`, `FilePath`, `CSVContent`
- Boolean: Usar `Is` o `Has` como prefijo → `IsValid`, `HasHeader`

---

## 2. Gestión de Código Fuente

### 2.1 Flujo de Trabajo Recomendado

#### ✅ OPCIÓN A: Desarrollo en IDE → Load → Compile (RECOMENDADO)

```bash
# 1. Editar archivos .cls en tu IDE favorito (VS Code)
# 2. Copiar archivos al contenedor (si no hay volumen compartido)
docker cp iris/src/demo/prod/MiClase.cls iris102:/opt/irisapp/iris/src/demo/prod/

# 3. Conectarse a IRIS
docker exec -it iris102 iris session IRIS -U DEMO

# 4. Cargar y compilar desde terminal IRIS
Do $system.OBJ.Load("/opt/irisapp/iris/src/demo/prod/MiClase.cls", "ck")

# 5. O compilar paquete completo
Do $system.OBJ.CompilePackage("Demo", "ckr")
```

#### ✅ OPCIÓN B: Usar Volúmenes Docker (MÁS SIMPLE)

```yaml
# En docker-compose.yml
services:
  iris:
    volumes:
      - ./iris/src:/opt/irisapp/iris/src:ro  # Read-only para seguridad
```

**Ventajas:**
- Cambios en archivos locales se reflejan inmediatamente en contenedor
- No necesitas copiar archivos manualmente
- Facilita el desarrollo iterativo

### 2.2 Comandos de Compilación

```objectscript
// Compilar una sola clase
Do $system.OBJ.Compile("Demo.MiClase", "ck")

// Compilar con recompilación de dependencias
Do $system.OBJ.Compile("Demo.MiClase", "ckr")

// Compilar paquete completo
Do $system.OBJ.CompilePackage("Demo", "ckr")

// Cargar desde archivo
Do $system.OBJ.Load("/path/to/file.cls", "ck")

// Verificar errores de compilación
Write $System.Status.GetErrorText($system.OBJ.Compile("Demo.MiClase", "ck"))
```

**Flags importantes:**
- `c` = Compile
- `k` = Keep source code loaded
- `r` = Recursive (recompilar dependencias)
- `d` = Display errors
- `u` = Update (no recompilar si no hay cambios)

### 2.3 El código va por stdin, nunca como argumento posicional

**❌ NO FUNCIONA:** pasar el código como argumento a `iris session` se interpreta
como nombre de rutina y devuelve `<INVALID ARGUMENT>`.
```bash
docker exec iris102 iris session IRIS -U DEMO "Do \$system.OBJ.CompilePackage(\"Demo\", \"ckr\")"
```

**✅ FORMA CORRECTA — heredoc por stdin, con `-i` en `docker exec`:**
El heredoc anterior fallaba porque a `docker exec` le faltaba `-i`: sin ese flag
no se conecta el stdin del host al del contenedor y el heredoc nunca llega a
`iris session`.
```bash
docker exec -i iris102 iris session IRIS -U DEMO <<'EOF'
Do $system.OBJ.Compile("Demo.Class", "ck")
Halt
EOF
```

Sirve igual para paquetes completos o scripts largos:
```bash
docker exec -i iris102 iris session IRIS -U DEMO <<'EOF'
Do $system.OBJ.CompilePackage("Demo", "ckr")
Halt
EOF
```

---

## 3. Compilación y Despliegue

### 3.1 Secuencia de Inicio de Production

```objectscript
// 1. Habilitar Interoperability en namespace (solo primera vez)
Do ##class(%EnsembleMgr).EnableNamespace("DEMO", 1)

// 2. Compilar todas las clases
Do $system.OBJ.CompilePackage("Demo", "ckr")

// 3. Iniciar Production
Do ##class(Ens.Director).StartProduction("Demo.Production")

// 4. Verificar estado
Write ##class(Ens.Director).IsProductionRunning()

// 5. Actualizar Production (después de cambios en XData)
Do ##class(Ens.Director).UpdateProduction()

// 6. Detener Production
Do ##class(Ens.Director).StopProduction()
```

### 3.2 Gestión de Credenciales

```objectscript
// Crear credenciales
Do ##class(Ens.Config.Credentials).SetCredential("MySQL-Demo-Credentials", "demo", "demo_pass", 1)

// Verificar credenciales
Set creds = ##class(Ens.Config.Credentials).%OpenId("MySQL-Demo-Credentials")
Write creds.Username

// Nota: El password no es recuperable directamente (encriptado)
```

### 3.3 Actualizar Configuración de Production

**Después de modificar XData en Production.cls:**

1. Compilar la clase
2. **Ejecutar UpdateProduction()** - ¡CRÍTICO!
3. Verificar en Portal que los cambios se aplicaron

```objectscript
// Secuencia completa
Do $system.OBJ.Compile("Demo.Production", "ck")
Do ##class(Ens.Director).UpdateProduction()
```

**⚠️ IMPORTANTE:** UpdateProduction() NO reinicia componentes automáticamente. Si cambias Settings críticos, es mejor Stop → Start.

---

## 4. Conectividad de Bases de Datos

### 4.1 ODBC vs JDBC vs SQL Gateway

#### 🔍 Conceptos Importantes (LECCIÓN CLAVE)

| Tecnología | Propósito | Cuándo Usar |
|------------|-----------|-------------|
| **ODBC DSN** | Conectar IRIS a bases de datos externas vía ODBC | SQL queries desde Business Operations |
| **JDBC** | Conectar IRIS a bases de datos externas vía Java | Cuando ODBC no está disponible o prefieres Java |
| **SQL Gateway Connections** | Configurar conexiones SQL persistentes | Queries complejos, múltiples tablas, joins |
| **External Language Servers** | Ejecutar código Java/.NET desde ObjectScript | Integración con librerías externas, NO para SQL |

**⚠️ ERROR COMÚN:** 
`Config.Gateways` crea **External Language Servers** (Java/.NET), NO conexiones SQL Gateway. Para SQL, usar ODBC DSN o crear SQL Gateway Connections desde Portal.

### 4.2 Configuración ODBC en Docker

**Archivo `/etc/odbc.ini`:**
```ini
[MySQL-Demo]
Driver=MariaDB ODBC 3.1 Driver
Server=mysql                    # Nombre del servicio en docker-compose
Port=3306
Database=demo
USER=demo
PASSWORD=demo_pass
Option=3

[PostgreSQL-Demo]
Driver=PostgreSQL Unicode
Servername=postgres             # Nombre del servicio en docker-compose
Port=5432
Database=demo
UserName=demo
Password=demo_pass
SSLmode=disable
```

**Archivo `/etc/odbcinst.ini`:**
```ini
[MariaDB ODBC 3.1 Driver]
Description=MariaDB Connector/ODBC v.3.1
Driver=/usr/lib/libmaodbc.so    # ARM64: /usr/lib/, x86: /usr/lib64/

[PostgreSQL Unicode]
Description=PostgreSQL ODBC driver (Unicode version)
Driver=/usr/lib/psqlodbcw.so
```

### 4.3 Verificación de Conectividad ODBC

```bash
# 1. Verificar drivers instalados
docker exec iris102 odbcinst -q -d

# 2. Verificar DSN configurados
docker exec iris102 odbcinst -q -s

# 3. Test de conexión con isql
docker exec iris102 isql MySQL-Demo demo demo_pass -v
docker exec iris102 isql PostgreSQL-Demo demo demo_pass -v

# 4. Query de prueba
docker exec iris102 isql MySQL-Demo demo demo_pass -v -c "SELECT 1;"
```

### 4.4 Uso de EnsLib.SQL.OutboundAdapter

```objectscript
Class Demo.MySQL.Operation Extends Ens.BusinessOperation
{
    Parameter ADAPTER = "EnsLib.SQL.OutboundAdapter";
    
    Property Adapter As EnsLib.SQL.OutboundAdapter;
    
    Method OnMessage(pRequest As Demo.Msg.DatabaseInsertRequest, 
                     Output pResponse As Demo.Msg.DatabaseInsertResponse) As %Status
    {
        // Crear statement
        Set stmt = ..Adapter.CreateStatement()
        
        // Preparar SQL con parámetros
        Set sql = "INSERT INTO csv_records (csv_id, name, age, city) VALUES (?, ?, ?, ?)"
        Set status = stmt.%Execute(csvId, name, age, city)
        
        // Verificar resultado
        If $$$ISERR(status) {
            // Manejar error
        }
        
        Return $$$OK
    }
}
```

**Settings en Production.cls:**
```xml
<Item Name="MySQLOperation" ClassName="Demo.MySQL.Operation">
    <Setting Target="Adapter" Name="DSN">MySQL-Demo</Setting>
    <Setting Target="Adapter" Name="Credentials">MySQL-Demo-Credentials</Setting>
</Item>
```

---
... (continúa con el resto del contenido completo de @BUENAS_PRACTICAS_IRIS.md)
```
### B) Contenido completo de @objectscript-cheat-sheet.md (insertado)
```markdown
# objectscript-cheat-sheet

ObjectScript Quick Reference

## Basics / SQL
Description | Command 
---------|----------
Call a class method|do ##class(package.class).method(arguments)
||set variable = ##class(package.class).method(arguments)
||_**Note**: place a . before each pass-by-reference argument_
Call an instance method|do object.method(arguments)
||set variable = object.method(arguments)
||_**Note**: place a . before each pass-by-reference argument_
Create a new object|set object = ##class(package.class).%New()
Open an existing object by ID|set object = ##class(package.class).%OpenId(id, concurrency, .status)
Open an existing object by unique index value|set object = ##class(package.class).IndexNameOpen(value, concurrency, .status)
Close an object (remove from process)|set object = ""
Write or set a property|write object.property
||set object.property = value
Write a class parameter|write ..#PARAMETER
||write ##class(package.class).#PARAMETER
...
(cheat-sheet completo insertado)
```