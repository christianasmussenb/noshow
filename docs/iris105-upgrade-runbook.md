# IRIS105 Upgrade And Operations Runbook

## Current state

The `iris105` container runs `intersystemsdc/irishealth-ml-community:2026.1` and publishes IRIS on host ports `52773` (web) and `1972` (superserver). The initial Community password convention is `SYS` for the `ADMIN` and `SUPERUSER` accounts.

The container is managed from `docker-compose.yml` and `.env.docker`. The workspace mounts source code, the chat application, and `docker/iris.init`. The old container had no Docker volumes, so its expired 2025.1 data was not reusable; projects were reinstalled from their repositories.

## Applications

- Management Portal: `http://localhost:52773/csp/sys/%25CSP.Portal.Home.zen`
- MLTEST API and UI: `/csp/mltest` and `/csp/mltest2`
- MANTEN API: `/csp/manten`
- MANTEN web: `/csp/manten-web/`
- MANTEN chat: `/csp/manten-chat/`

The `MLTEST` and `MANTEN` namespaces coexist in the same IRIS instance. New applications must use their own CSP path and namespace and must not overwrite existing web application definitions.

## Recreate procedure

1. Confirm the image is available with `docker images`.
2. Confirm the old container and its mounts with `docker inspect iris105`.
3. Start with `docker compose --env-file .env.docker up -d`.
4. Wait for the Management Portal to return HTTP 200.
5. Create or restore namespaces before importing classes.
6. Import classes package by package when the source tree contains nested package directories; `LoadDir` does not recursively load every nested directory in all workflows.
7. Run each project's setup script and data loader.
8. Validate local HTTP endpoints before starting Cloudflare.

## Troubleshooting lessons

- An expired Community image fails during startup with a license error; upgrading only the container command is insufficient if the image tag remains `latest`.
- A REST web application can exist and still return `404` if `NameSpace` or `DispatchClass` was not persisted. Inspect `Security.Applications.Get()` after registration.
- IRIS role matching requires the `:%All` form for an unauthenticated demo application. `%All` alone can produce an application that still fails at runtime.
- A tunnel can have a valid DNS CNAME and still return Cloudflare `1033` when no `cloudflared tunnel run` process is connected.
- Keep Cloudflare credentials outside Git and store only a redacted config template in the repository.
