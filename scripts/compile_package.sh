#!/usr/bin/env bash
# Small helper to compile the IRIS105 package inside a running IRIS container
# Usage:
#   ./scripts/compile_package.sh <container-name> [namespace]
# Example:
#   ./scripts/compile_package.sh iris MLTEST

set -euo pipefail
container=${1:-iris}
namespace=${2:-%SYS}

echo "Compiling IRIS105 package in container '${container}' namespace '${namespace}'"

# Use iris session to run compile command inside container.
# El código va por stdin: como argumento posicional se interpreta como nombre
# de rutina y devuelve <INVALID ARGUMENT>.
docker exec -i "${container}" iris session IRIS -U "${namespace}" <<EOF
Do \$system.OBJ.CompilePackage("IRIS105","ckr")
Halt
EOF

echo "Compile command finished. Check container logs for errors or run 'iris session' to inspect."