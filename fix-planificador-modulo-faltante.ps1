# ============================================================================
# ObrasPlan - Fix Planificador (PARTE 3/3 - CORRECCION): el build de Vercel
# fallaba con "Module not found: Can't resolve '@/lib/utils/planificadorRango'"
# en el commit 5912091.
#
# DIAGNOSTICO (confirmado comparando GitHub commit por commit, sin tocar
# nada en Supabase ni borrar datos):
#   El commit 5d7bd20 (primera entrega de hoy) SOLO llego a subir a GitHub
#   el propio script fix-planificador-historico.ps1 (176 lineas) - los
#   archivos que ese script debia escribir y confirmar por su cuenta
#   (planificadorRango.ts, planificadorRango.test.ts, vitest.config.mts,
#   y los cambios de package.json) NUNCA llegaron a quedar registrados en
#   git en tu maquina, aunque el propio script si paso sus verificaciones
#   de tamano/contenido. src/app/planificacion/page.tsx SI se guardo bien
#   (su codigo ya incluye las dos correcciones de hoy, confirmado
#   comparando byte a byte con GitHub) - por eso el sintoma que viste no
#   era "faltan datos" sino un build roto: page.tsx importa un archivo
#   (planificadorRango.ts) que nunca llego a subirse.
#
#   El commit 5912091 (segunda entrega, paginacion) si subio bien sus 2
#   archivos nuevos (fetchAllPaginated.ts y su test) porque ese script no
#   dependia de que la entrega anterior hubiera llegado a git para escribir
#   los suyos.
#
# ESTE SCRIPT solo anade lo que de verdad falta en GitHub ahora mismo
# (comprobado archivo por archivo contra origin/main antes de generarlo):
#   1) src/lib/utils/planificadorRango.ts        (NUEVO - faltaba entero)
#   2) src/lib/utils/planificadorRango.test.ts   (NUEVO - faltaba entero)
#   3) vitest.config.mts                         (NUEVO - faltaba entero)
#   4) package.json                              (solo le faltaban 2 scripts
#                                                  npm + vitest como devDependency)
# NO se toca src/app/planificacion/page.tsx ni fetchAllPaginated.ts/.test.ts:
# ya estan correctos en GitHub, y no hace falta arriesgarse a pisarlos.
#
# MEJORA respecto a los scripts anteriores: ahora cada comando git
# (pull/add/commit/push) comprueba su propio codigo de salida y PARA el
# script con un mensaje claro si algo falla, en vez de seguir en silencio
# como pudo pasar la primera vez.
#
# No hay migraciones SQL en este cambio. No se ha modificado ni eliminado
# ningun dato de produccion.
# ============================================================================

$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan"
Set-Location $RepoPath
Write-Host "Directorio de trabajo actual: $(Get-Location)" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

Write-Host "== git pull ==" -ForegroundColor Cyan
git pull
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git pull ha fallado (codigo $LASTEXITCODE). Revisa el mensaje de arriba (por ejemplo cambios locales sin confirmar, o conflicto) y resuelvelo antes de continuar. El script se detiene aqui." -ForegroundColor Red; exit 1 }

Write-Host "== Comprobando que estamos en el repositorio correcto ==" -ForegroundColor Cyan
$originUrl = git config --get remote.origin.url
Write-Host "   remote.origin.url = $originUrl" -ForegroundColor Cyan
if ($originUrl -notlike "*Lauroba/obrasplan*") { Write-Host "ERROR: esta carpeta no apunta al repositorio Lauroba/obrasplan (apunta a: $originUrl). Verifica `$RepoPath. El script se detiene aqui." -ForegroundColor Red; exit 1 }
$topLevel = git rev-parse --show-toplevel
Write-Host "   raiz real del repo git = $topLevel" -ForegroundColor Cyan

# ----------------------------------------------------------------------------
# src/lib/utils/planificadorRango.ts
# Archivo que FALTABA en GitHub (por eso fallaba el build: 'Module not found: Cant resolve @/lib/utils/planificadorRango'). Logica pura (sin React/Supabase) que calcula el rango de fechas [fromDs, toDs] que el Planificador debe pedir.
# SHA256 original: 982cc17b66b736b6a64d86001b9f0bd9c78acde6584df597eb22ccb966f692ad
# ----------------------------------------------------------------------------
Write-Host "== Escribiendo src/lib/utils/planificadorRango.ts ==" -ForegroundColor Cyan
$b64_src_lib_utils_planificadorRango_ts = @"
LyoqCiAqIHNyYy9saWIvdXRpbHMvcGxhbmlmaWNhZG9yUmFuZ28udHMKICoKICogQ2FsY3VsbyBwdXJvIGRlbCByYW5nbyBkZSBmZWNoYXMgcXVlIGVsIFBsYW5pZmljYWRvciBwaWRlIGEgU3VwYWJhc2UgcGFyYQogKiBsYSB0YWJsYSBgYXNpZ25hY2lvbmVzYCwgZW4gZnVuY2lvbiBkZWwgcmFuZ28gUkVBTE1FTlRFIHZpc2libGUKICogKHN0YXJ0RGF0ZSAuLiBzdGFydERhdGUgKyBkaWFzVmlzaWJsZXMgLSAxKSwgY29uIHVuIG1hcmdlbiBkZSBwcmVmZXRjaAogKiBwYXJhIHF1ZSBsYSBuYXZlZ2FjaW9uIChzZW1hbmEvbWVzL2HDsW8sIGZsZWNoYXMsICJIb3kiKSBzZSBzaWVudGEgZmx1aWRhCiAqIHNpbiBkaXNwYXJhciB1bmEgY29uc3VsdGEgcG9yIGNhZGEgZGlhLgogKgogKiBFeHRyYWlkbyBkZSBzcmMvYXBwL3BsYW5pZmljYWNpb24vcGFnZS50c3ggY29tbyBwYXJ0ZSBkZWwgZml4IGRlbCBidWc6CiAqICJlbCBQbGFuaWZpY2Fkb3Igbm8gbXVlc3RyYSBhc2lnbmFjaW9uZXMgaGlzdG9yaWNhcyBkZSBqdWxpbyAyMDI2IHkKICogbWVzZXMgYW50ZXJpb3JlcyIgKGluZm9ybWUgMDgvMDkvMjAyNikuCiAqCiAqIENhdXNhIHJhaXo6IGVsIHJhbmdvIHNlIGNhbGN1bGFiYSBVTkEgVU5JQ0EgVkVaIGFsIG1vbnRhciBlbCBjb21wb25lbnRlCiAqIChkZW50cm8gZGUgdW4gdXNlQ2FsbGJhY2sgY29uIGRlcGVuZGVuY2lhcyB2YWNpYXMpLCB0b21hbmRvIGVsIHN0YXJ0RGF0ZQogKiBkZSBlc2UgaW5zdGFudGUuIEFsIG5hdmVnYXIgY29uIGxhcyBmbGVjaGFzIG8gIkhveSIsIHN0YXJ0RGF0ZSBjYW1iaWFiYQogKiBwZXJvIGxhIGZ1bmNpb24gZGUgZmV0Y2ggbnVuY2Egc2Ugdm9sdmlhIGEgZWplY3V0YXIsIGFzaSBxdWUgbGEgdmVudGFuYQogKiBkZSBkYXRvcyBjYXJnYWRhIHF1ZWRhYmEgY29uZ2VsYWRhIGEgbGEgZmVjaGEgZGUgYXBlcnR1cmEgZGUgbGEgcGFnaW5hOgogKiB0b2RvIGxvIGFudGVyaW9yIGEgZXNhIHZlbnRhbmEgZGVqYWJhIGRlIGVzdGFyIGVuIG1lbW9yaWEgeSBkZXNhcGFyZWNpYQogKiBkZWwgY2FsZW5kYXJpbywgYXVucXVlIGVsIHJlZ2lzdHJvIHNpZ3VpZXJhIGludGFjdG8gZW4gU3VwYWJhc2UgKEZpY2hhCiAqIE9icmEgeSBGaWNoYSBSUkhILCBxdWUgbm8gZmlsdHJhbiBwb3IgZmVjaGEsIGxvIHNlZ3VpYW4gbW9zdHJhbmRvIGJpZW4pLgogKgogKiBFbCBmaXg6IGNhbGN1bGFyIGVsIHJhbmdvIGEgcGFydGlyIGRlbCByYW5nbyBSRUFMTUVOVEUgdmlzaWJsZSAocXVlCiAqIGRlcGVuZGUgZGUgc3RhcnREYXRlIFkgZGVsIHZpZXdNb2RlLCB5YSBxdWUgImHDsW8iIHBpbnRhIG11Y2hvcyBtYXMgZGlhcwogKiBxdWUgInNlbWFuYSIpIHkgcmVjYWxjdWxhcmxvL3JlZmV0Y2hlYXIgY2FkYSB2ZXogcXVlIGN1YWxxdWllcmEgZGUgbG9zCiAqIGRvcyBjYW1iaWEuCiAqLwoKLy8gTWFyZ2VuIGRlIHByZWZldGNoIGFscmVkZWRvciBkZWwgcmFuZ28gdmlzaWJsZSwgZW4gZGlhcy4gTWFudGllbmUgbGEKLy8gbmF2ZWdhY2lvbiBmbHVpZGEgKG5vIGhheSBxdWUgcmVmZXRjaGVhciBlbiBjYWRhIGNsaWNrIHNpIHRlIG11ZXZlcwovLyBkZW50cm8gZGUgZXN0YSB2ZW50YW5hKSBzaW4gY2FyZ2FyIHRvZG8gZWwgaGlzdG9yaWNvIGRlIGdvbHBlLgpjb25zdCBNQVJHRU5fQVRSQVNfRElBUyA9IDI4Owpjb25zdCBNQVJHRU5fQURFTEFOVEVfRElBUyA9IDU2OwoKZnVuY3Rpb24gdG9EUyhkOiBEYXRlKTogc3RyaW5nIHsKICByZXR1cm4gYCR7ZC5nZXRGdWxsWWVhcigpfS0ke1N0cmluZyhkLmdldE1vbnRoKCkgKyAxKS5wYWRTdGFydCgyLCAiMCIpfS0ke1N0cmluZyhkLmdldERhdGUoKSkucGFkU3RhcnQoMiwgIjAiKX1gOwp9CgpleHBvcnQgaW50ZXJmYWNlIFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMgewogIGZyb21Eczogc3RyaW5nOwogIHRvRHM6IHN0cmluZzsKfQoKLyoqCiAqIENhbGN1bGEgZWwgcmFuZ28gW2Zyb21EcywgdG9Ec10gKFlZWVktTU0tREQsIGluY2x1c2l2ZSkgYSBwZWRpciBhCiAqIFN1cGFiYXNlIHBhcmEgY3VicmlyIHRvZG8gbG8gcXVlIGVsIFBsYW5pZmljYWRvciB2YSBhIHBpbnRhci4KICoKICogQHBhcmFtIHN0YXJ0RGF0ZSAgICAgUHJpbWVyIGRpYSB2aXNpYmxlIGVuIGVsIGNhbGVuZGFyaW8gKGVsIHN0YXJ0RGF0ZSBkZWwgY29tcG9uZW50ZSkuCiAqIEBwYXJhbSBkaWFzVmlzaWJsZXMgIE51bWVybyBkZSBkaWFzIHF1ZSBzZSBwaW50YW4gYSBwYXJ0aXIgZGUgc3RhcnREYXRlIChEQVlTX0NPVU5UW3ZpZXdNb2RlXSkuCiAqLwpleHBvcnQgZnVuY3Rpb24gZ2V0UmFuZ29GZXRjaEFzaWduYWNpb25lcyhzdGFydERhdGU6IERhdGUsIGRpYXNWaXNpYmxlczogbnVtYmVyKTogUmFuZ29GZXRjaEFzaWduYWNpb25lcyB7CiAgY29uc3QgdmlzaWJsZVN0YXJ0ID0gbmV3IERhdGUoc3RhcnREYXRlLmdldEZ1bGxZZWFyKCksIHN0YXJ0RGF0ZS5nZXRNb250aCgpLCBzdGFydERhdGUuZ2V0RGF0ZSgpKTsKICBjb25zdCB2aXNpYmxlRW5kID0gbmV3IERhdGUodmlzaWJsZVN0YXJ0KTsKICB2aXNpYmxlRW5kLnNldERhdGUodmlzaWJsZUVuZC5nZXREYXRlKCkgKyBNYXRoLm1heChkaWFzVmlzaWJsZXMsIDEpIC0gMSk7CgogIGNvbnN0IHJzID0gbmV3IERhdGUodmlzaWJsZVN0YXJ0KTsKICBycy5zZXREYXRlKHJzLmdldERhdGUoKSAtIE1BUkdFTl9BVFJBU19ESUFTKTsKICBjb25zdCByZSA9IG5ldyBEYXRlKHZpc2libGVFbmQpOwogIHJlLnNldERhdGUocmUuZ2V0RGF0ZSgpICsgTUFSR0VOX0FERUxBTlRFX0RJQVMpOwoKICByZXR1cm4geyBmcm9tRHM6IHRvRFMocnMpLCB0b0RzOiB0b0RTKHJlKSB9Owp9CgovKiogdHJ1ZSBzaSBgZmVjaGFgIChZWVlZLU1NLUREKSBjYWUgZGVudHJvIGRlIGByYW5nb2AgKGluY2x1c2l2ZSkuICovCmV4cG9ydCBmdW5jdGlvbiBmZWNoYUVuUmFuZ28oZmVjaGE6IHN0cmluZywgcmFuZ286IFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMpOiBib29sZWFuIHsKICByZXR1cm4gZmVjaGEgPj0gcmFuZ28uZnJvbURzICYmIGZlY2hhIDw9IHJhbmdvLnRvRHM7Cn0KCi8qKgogKiB0cnVlIHNpIHVuYSBhc2lnbmFjaW9uIChwb3IgZmVjaGFfaW5pY2lvL2ZlY2hhX2ZpbikgU09MQVBBIGVsIHJhbmdvIGRhZG8uCiAqIE1pc21hIGxvZ2ljYSBkZSBzb2xhcGFtaWVudG8gcXVlIGFwbGljYSBsYSBxdWVyeSByZWFsIGRlIFN1cGFiYXNlCiAqICguZ3RlKCJmZWNoYV9maW4iLCBmcm9tRHMpLmx0ZSgiZmVjaGFfaW5pY2lvIiwgdG9EcykpIHkgcXVlIGxhIGxpc3RhIGRlCiAqIHJlcXVpc2l0b3MgZGVsIFBsYW5pZmljYWRvciAoYXNzaWdubWVudC5zdGFydCA8PSB2aXNpYmxlRW5kIEFORAogKiBhc3NpZ25tZW50LmVuZCA+PSB2aXNpYmxlU3RhcnQpLgogKi8KZXhwb3J0IGZ1bmN0aW9uIGFzaWduYWNpb25Tb2xhcGFSYW5nbygKICBhc2lnbmFjaW9uOiB7IGZlY2hhX2luaWNpbzogc3RyaW5nOyBmZWNoYV9maW46IHN0cmluZyB9LAogIHJhbmdvOiBSYW5nb0ZldGNoQXNpZ25hY2lvbmVzCik6IGJvb2xlYW4gewogIHJldHVybiBhc2lnbmFjaW9uLmZlY2hhX2ZpbiA+PSByYW5nby5mcm9tRHMgJiYgYXNpZ25hY2lvbi5mZWNoYV9pbmljaW8gPD0gcmFuZ28udG9EczsKfQo=
"@
$bytes_src_lib_utils_planificadorRango_ts = [System.Convert]::FromBase64String($b64_src_lib_utils_planificadorRango_ts)
$dest_src_lib_utils_planificadorRango_ts = Join-Path $RepoPath "src\lib\utils\planificadorRango.ts"
$dir_src_lib_utils_planificadorRango_ts = Split-Path $dest_src_lib_utils_planificadorRango_ts -Parent
if (!(Test-Path $dir_src_lib_utils_planificadorRango_ts)) { New-Item -ItemType Directory -Force -Path $dir_src_lib_utils_planificadorRango_ts | Out-Null }
[System.IO.File]::WriteAllBytes($dest_src_lib_utils_planificadorRango_ts, $bytes_src_lib_utils_planificadorRango_ts)
$size_src_lib_utils_planificadorRango_ts = (Get-Item $dest_src_lib_utils_planificadorRango_ts).Length
Write-Host "   src/lib/utils/planificadorRango.ts: $size_src_lib_utils_planificadorRango_ts bytes escritos (esperado 3593) en $($dest_src_lib_utils_planificadorRango_ts)" -ForegroundColor Green
if ($size_src_lib_utils_planificadorRango_ts -ne 3593) { Write-Host "   ERROR: tamano no coincide para src/lib/utils/planificadorRango.ts" -ForegroundColor Red; exit 1 }

# ----------------------------------------------------------------------------
# src/lib/utils/planificadorRango.test.ts
# Archivo que tambien faltaba en GitHub. Pruebas de regresion (Vitest) del bug de asignaciones historicas de julio 2026.
# SHA256 original: 393749d72b801800135a98e5e9cef467cf27b2a50f04e2715782ae0e1b1a5ede
# ----------------------------------------------------------------------------
Write-Host "== Escribiendo src/lib/utils/planificadorRango.test.ts ==" -ForegroundColor Cyan
$b64_src_lib_utils_planificadorRango_test_ts = @"
LyoqCiAqIFBydWViYXMgZGUgcmVncmVzacOzbiBwYXJhIGVsIGZpeCBkZWwgYnVnOgogKiAiZWwgUGxhbmlmaWNhZG9yIG5vIG11ZXN0cmEgYXNpZ25hY2lvbmVzIGhpc3TDs3JpY2FzIGRlIGp1bGlvIDIwMjYgeQogKiBtZXNlcyBhbnRlcmlvcmVzIiAoaW5mb3JtZSAwOC8wOS8yMDI2KS4KICoKICogQ2F1c2EgcmHDrXo6IGVsIHJhbmdvIGRlIGZlY2hhcyBwZWRpZG8gYSBTdXBhYmFzZSBzZSBjYWxjdWxhYmEgVU5BIFNPTEEKICogVkVaIGFsIG1vbnRhciBlbCBjb21wb25lbnRlICh1c2VDYWxsYmFjayBjb24gZGVwZW5kZW5jaWFzIHZhY8OtYXMpIGEKICogcGFydGlyIGRlbCBgc3RhcnREYXRlYCBkZSBlc2UgaW5zdGFudGUsIHkgbnVuY2Egc2UgcmVjYWxjdWxhYmEgYWwKICogbmF2ZWdhciBjb24gbGFzIGZsZWNoYXMgLyAiSG95IiAvIGNhbWJpYXIgZGUgdmlzdGEgKHNlbWFuYS9tZXMvYcOxbykuCiAqIEVzdGFzIHBydWViYXMgY3VicmVuIGxhIGzDs2dpY2EgUFVSQSBxdWUgc3VzdGl0dXllIGEgZXNlIGPDoWxjdWxvCiAqIChleHRyYcOtZGEgYSBnZXRSYW5nb0ZldGNoQXNpZ25hY2lvbmVzKSwgdXNhbmRvIGNvbW8gdHJhemFkb3IgZWwgY2FzbwogKiByZWFsIHZlcmlmaWNhZG8gZW4gU3VwYWJhc2U6IE1VUlBST1RFQyAtIEVTVEVMTEEgKFIpLCBJb251dCBGIC8gWmlnb3IgTwogKiAvIEtBTkdPTy0xODUyTVpGLCAwNy8wNy8yMDI2LgogKgogKiBOb3RhIGRlIGNvYmVydHVyYTogbG9zIHRlc3RzIDEtNSBkZWwgaW5mb3JtZSBzZSB2ZXJpZmljYW4gYXF1w60gYSBuaXZlbAogKiBkZSBsYSBmdW5jacOzbiBwdXJhIHF1ZSBkZWNpZGUgcXXDqSByYW5nbyBzZSBwaWRlIGEgU3VwYWJhc2UgKHF1ZSBlcwogKiBleGFjdGFtZW50ZSBkb25kZSBlc3RhYmEgZWwgYnVnKS4gRWwgdGVzdCA2IChvYnJhIEZhY3R1cmFkYSAvIEZpbmFsaXphZGEKICogLyBBcmNoaXZhZGEgc2lndWUgbW9zdHJhbmRvIGhpc3TDs3JpY28pIG5vIGRlcGVuZGUgZGUgZXN0YSBmdW5jacOzbiAtLW5pCiAqIGVzdGEgbmkgbGEgcXVlcnkgcmVhbCBkZSBTdXBhYmFzZSBmaWx0cmFuIHBvciBlc3RhZG8gZGUgbGEgb2JyYSBlbgogKiBuaW5nw7puIHB1bnRvLS0geSBzZSB2ZXJpZmljYSBwb3IgaW5zcGVjY2nDs24gZGUgY8OzZGlnbyBtw6FzIGxhCiAqIGNvbXByb2JhY2nDs24gbWFudWFsIGRlIGFjZXB0YWNpw7NuIChzZWNjacOzbiAxNCBkZWwgaW5mb3JtZTogTVVSUFJPVEVDCiAqIGVzdMOhIGFjdHVhbG1lbnRlICI2LUZhY3R1cmFkbyIgeSBzdSBhc2lnbmFjacOzbiBkZWwgMDcvMDcgc2UgbG9jYWxpesOzCiAqIHNpbiBwcm9ibGVtYSkuIE5vIGhheSBpbmZyYWVzdHJ1Y3R1cmEgZGUgdGVzdHMgZGUgY29tcG9uZW50ZXMgKFJUTCkgZW4KICogZWwgcmVwbyB0b2RhdsOtYTsgYcOxYWRpcmxhIGVzIHVuIGNhbWJpbyBtYXlvciBxdWUgbm8gc2UgaGEgaGVjaG8gcGFyYSBubwogKiBzb2JyZWRpbWVuc2lvbmFyIGVzdGUgZml4LgogKi8KaW1wb3J0IHsgZGVzY3JpYmUsIGV4cGVjdCwgaXQgfSBmcm9tICJ2aXRlc3QiOwppbXBvcnQgeyBhc2lnbmFjaW9uU29sYXBhUmFuZ28sIGZlY2hhRW5SYW5nbywgZ2V0UmFuZ29GZXRjaEFzaWduYWNpb25lcyB9IGZyb20gIi4vcGxhbmlmaWNhZG9yUmFuZ28iOwoKY29uc3QgV0VFSyA9IDc7CmNvbnN0IE1PTlRIID0gMzE7CmNvbnN0IFlFQVIgPSAzNjQ7CgovLyBJb251dCBGIC8gWmlnb3IgTywgTVVSUFJPVEVDIC0gRVNURUxMQSAoUikKY29uc3QgYXNpZ25hY2lvbklvbnV0N0p1bGlvID0geyBmZWNoYV9pbmljaW86ICIyMDI2LTA3LTA3IiwgZmVjaGFfZmluOiAiMjAyNi0wNy0wNyIgfTsKLy8gS0FOR09PLTE4NTJNWkYgKG1pc21vIGTDrWEsIG90cmEgb2JyYS9yZWN1cnNvLCBtaXNtYSBmZWNoYSkKY29uc3QgYXNpZ25hY2lvbkthbmdvbzdKdWxpbyA9IHsgZmVjaGFfaW5pY2lvOiAiMjAyNi0wNy0wNyIsIGZlY2hhX2ZpbjogIjIwMjYtMDctMDciIH07Ci8vIEVqZW1wbG8gZGUgc2VjY2nDs24gMTQ6IDExLzA1LzIwMjYKY29uc3QgYXNpZ25hY2lvbjExTWF5byA9IHsgZmVjaGFfaW5pY2lvOiAiMjAyNi0wNS0xMSIsIGZlY2hhX2ZpbjogIjIwMjYtMDUtMTEiIH07Ci8vIEFzaWduYWNpw7NuIGRlIGFnb3N0byAoZWplbXBsbyBkZWwgaW5mb3JtZTogTHVjaWFuIEMgLyBNaWhhaWwgQiAvIFZhc2lsZSBFLCAxMy8wOC8yMDI2KQpjb25zdCBhc2lnbmFjaW9uMTNBZ29zdG8gPSB7IGZlY2hhX2luaWNpbzogIjIwMjYtMDgtMTMiLCBmZWNoYV9maW46ICIyMDI2LTA4LTEzIiB9OwoKZGVzY3JpYmUoImdldFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMg4oCUIFBsYW5pZmljYWRvciAoZml4IGhpc3TDs3JpY28ganVsaW8vYWdvc3RvIDIwMjYpIiwgKCkgPT4gewogIGl0KCJUZXN0IDE6IHVuYSBhc2lnbmFjacOzbiBkZSBwZXJzb25hIGVuIGp1bGlvIGFwYXJlY2UgYWwgYWJyaXIganVsaW8iLCAoKSA9PiB7CiAgICAvLyBMdW5lcyBkZSBsYSBzZW1hbmEgcXVlIGNvbnRpZW5lIGVsIDA3LzA3LzIwMjYKICAgIGNvbnN0IHJhbmdvID0gZ2V0UmFuZ29GZXRjaEFzaWduYWNpb25lcyhuZXcgRGF0ZSgyMDI2LCA2LCA2KSwgV0VFSyk7CiAgICBleHBlY3QoYXNpZ25hY2lvblNvbGFwYVJhbmdvKGFzaWduYWNpb25Jb251dDdKdWxpbywgcmFuZ28pKS50b0JlKHRydWUpOwogIH0pOwoKICBpdCgiVGVzdCAyOiB1bmEgYXNpZ25hY2nDs24gZGUgdmVow61jdWxvIGVuIGp1bGlvIGFwYXJlY2UgYWwgYWJyaXIganVsaW8iLCAoKSA9PiB7CiAgICBjb25zdCByYW5nbyA9IGdldFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMobmV3IERhdGUoMjAyNiwgNiwgNiksIFdFRUspOwogICAgZXhwZWN0KGFzaWduYWNpb25Tb2xhcGFSYW5nbyhhc2lnbmFjaW9uS2FuZ29vN0p1bGlvLCByYW5nbykpLnRvQmUodHJ1ZSk7CiAgfSk7CgogIGl0KCJUZXN0IDM6IHVuYSBhc2lnbmFjacOzbiBkZSBwZXJzb25hIGVuIG1heW8gYXBhcmVjZSBhbCBhYnJpciBtYXlvIiwgKCkgPT4gewogICAgLy8gTHVuZXMgZGUgbGEgc2VtYW5hIHF1ZSBjb250aWVuZSBlbCAxMS8wNS8yMDI2CiAgICBjb25zdCByYW5nbyA9IGdldFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMobmV3IERhdGUoMjAyNiwgNCwgMTEpLCBXRUVLKTsKICAgIGV4cGVjdChhc2lnbmFjaW9uU29sYXBhUmFuZ28oYXNpZ25hY2lvbjExTWF5bywgcmFuZ28pKS50b0JlKHRydWUpOwogIH0pOwoKICBpdCgiVGVzdCA0OiB1bmEgYXNpZ25hY2nDs24gZGUgYWdvc3RvIHNpZ3VlIGZ1bmNpb25hbmRvIiwgKCkgPT4gewogICAgY29uc3QgcmFuZ28gPSBnZXRSYW5nb0ZldGNoQXNpZ25hY2lvbmVzKG5ldyBEYXRlKDIwMjYsIDcsIDEwKSwgV0VFSyk7CiAgICBleHBlY3QoYXNpZ25hY2lvblNvbGFwYVJhbmdvKGFzaWduYWNpb24xM0Fnb3N0bywgcmFuZ28pKS50b0JlKHRydWUpOwogIH0pOwoKICBpdCgiVGVzdCA1OiBuYXZlZ2FyIGp1bGlvIOKGkiBhZ29zdG8g4oaSIGp1bGlvIG11ZXN0cmEgbGFzIGFzaWduYWNpb25lcyBjb3JyZWN0YW1lbnRlIGVuIGFtYm9zIHBhc29zIHBvciBqdWxpbyIsICgpID0+IHsKICAgIGNvbnN0IHJhbmdvSnVsaW8xID0gZ2V0UmFuZ29GZXRjaEFzaWduYWNpb25lcyhuZXcgRGF0ZSgyMDI2LCA2LCA2KSwgV0VFSyk7CiAgICBleHBlY3QoYXNpZ25hY2lvblNvbGFwYVJhbmdvKGFzaWduYWNpb25Jb251dDdKdWxpbywgcmFuZ29KdWxpbzEpKS50b0JlKHRydWUpOwoKICAgIGNvbnN0IHJhbmdvQWdvc3RvID0gZ2V0UmFuZ29GZXRjaEFzaWduYWNpb25lcyhuZXcgRGF0ZSgyMDI2LCA3LCAxMCksIFdFRUspOwogICAgZXhwZWN0KGFzaWduYWNpb25Tb2xhcGFSYW5nbyhhc2lnbmFjaW9uMTNBZ29zdG8sIHJhbmdvQWdvc3RvKSkudG9CZSh0cnVlKTsKICAgIC8vIEFsIGVzdGFyIGVuIGFnb3N0bywganVsaW8gcHVlZGUgbyBubyBlc3RhciBjdWJpZXJ0byBwb3IgZWwgbWFyZ2VuIGRlIHByZWZldGNoLAogICAgLy8gcGVybyBlc28gZXMgYWNlcHRhYmxlOiBsbyBxdWUgTlVOQ0EgZGViZSBwYXNhciBlcyBxdWUganVsaW8gZGVqZSBkZSBjYXJnYXJzZQogICAgLy8gYWwgdm9sdmVyIGEgbmF2ZWdhciBoYWNpYSBhdHLDoXMgKGxvIHF1ZSBzw60gY29tcHJ1ZWJhIGxhIHNpZ3VpZW50ZSBhc2VyY2nDs24pLgoKICAgIGNvbnN0IHJhbmdvSnVsaW8yID0gZ2V0UmFuZ29GZXRjaEFzaWduYWNpb25lcyhuZXcgRGF0ZSgyMDI2LCA2LCA2KSwgV0VFSyk7CiAgICBleHBlY3QocmFuZ29KdWxpbzIpLnRvRXF1YWwocmFuZ29KdWxpbzEpOyAvLyBmdW5jacOzbiBwdXJhOiBtaXNtbyBpbnB1dCAtPiBtaXNtbyBvdXRwdXQsIHNpbiBjYWNow6kgbmkgZXN0YWRvIGNvbGdhZG8KICAgIGV4cGVjdChhc2lnbmFjaW9uU29sYXBhUmFuZ28oYXNpZ25hY2lvbklvbnV0N0p1bGlvLCByYW5nb0p1bGlvMikpLnRvQmUodHJ1ZSk7CiAgfSk7CgogIGl0KCJhbnRlcyBkZWwgZml4IChyYW5nbyBmaWpvIGNhbGN1bGFkbyBzb2xvIGFsIG1vbnRhcikgZXN0ZSBtaXNtbyBlc2NlbmFyaW8gZmFsbGFiYTogbmF2ZWdhciBhIGp1bGlvIG5vIHJlY2FsY3VsYWJhIGVsIHJhbmdvIHkgbGEgdmVudGFuYSBxdWVkYWJhIGFuY2xhZGEgYSBsYSBmZWNoYSBkZSBhcGVydHVyYSBkZSBsYSBww6FnaW5hIiwgKCkgPT4gewogICAgLy8gU2ltdWxhbW9zIGVsIGNvbXBvcnRhbWllbnRvIEFOVElHVU86IGVsIHJhbmdvIHNlIGNhbGN1bGEgdW5hIHZleiBjb24gZWwKICAgIC8vIHN0YXJ0RGF0ZSBkZSAiaG95IiAoYXBlcnR1cmEgZGUgcMOhZ2luYSwgcC5lai4gcHJpbmNpcGlvcyBkZSBzZXB0aWVtYnJlKSB5CiAgICAvLyBudW5jYSBzZSB2dWVsdmUgYSBjYWxjdWxhciBhbCBuYXZlZ2FyIGEganVsaW8uCiAgICBjb25zdCByYW5nb0NhbGN1bGFkb0FsQWJyaXJMYVBhZ2luYSA9IGdldFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMobmV3IERhdGUoMjAyNiwgOCwgNyksIFdFRUspOyAvLyBsdW5lcyAwNy8wOS8yMDI2CiAgICAvLyBKdWxpbyBxdWVkYSBmdWVyYSBkZSBlc2EgdmVudGFuYSBjb25nZWxhZGEgLT4gZXN0ZSBlcyBlbCBidWcgcmVwb3J0YWRvLgogICAgZXhwZWN0KGFzaWduYWNpb25Tb2xhcGFSYW5nbyhhc2lnbmFjaW9uSW9udXQ3SnVsaW8sIHJhbmdvQ2FsY3VsYWRvQWxBYnJpckxhUGFnaW5hKSkudG9CZShmYWxzZSk7CgogICAgLy8gQ29uIGVsIGZpeCwgYWwgbmF2ZWdhciBhIGp1bGlvIFPDjSBzZSByZWNhbGN1bGEgZWwgcmFuZ28gY29uIGVsIHN0YXJ0RGF0ZSByZWFsIGRlIGp1bGlvOgogICAgY29uc3QgcmFuZ29SZWNhbGN1bGFkb0FsTmF2ZWdhckFKdWxpbyA9IGdldFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMobmV3IERhdGUoMjAyNiwgNiwgNiksIFdFRUspOwogICAgZXhwZWN0KGFzaWduYWNpb25Tb2xhcGFSYW5nbyhhc2lnbmFjaW9uSW9udXQ3SnVsaW8sIHJhbmdvUmVjYWxjdWxhZG9BbE5hdmVnYXJBSnVsaW8pKS50b0JlKHRydWUpOwogIH0pOwoKICBpdCgibGEgdmlzdGEgJ2HDsW8nICgzNjQgZMOtYXMgdmlzaWJsZXMpIHRhbWJpw6luIHF1ZWRhIGN1YmllcnRhLCBubyBzb2xvICdzZW1hbmEnLydtZXMnIiwgKCkgPT4gewogICAgLy8gQW50ZXMgZGVsIGZpeCwgaW5jbHVzbyBTSU4gbmF2ZWdhciwgbGEgdmlzdGEgYcOxbyBwaW50YWJhIDM2NCBkw61hcyBwZXJvIHNvbG8gc2UKICAgIC8vIGNhcmdhYmEgdW5hIHZlbnRhbmEgZmlqYSBkZSA4NCBkw61hcyAtPiBncmFuIHBhcnRlIGRlbCBhw7FvIHF1ZWRhYmEgdmFjw61hLgogICAgY29uc3QgaW5pY2lvQW5pbyA9IG5ldyBEYXRlKDIwMjYsIDAsIDUpOyAvLyBsdW5lcyAwNS8wMS8yMDI2CiAgICBjb25zdCByYW5nbyA9IGdldFJhbmdvRmV0Y2hBc2lnbmFjaW9uZXMoaW5pY2lvQW5pbywgWUVBUik7CiAgICBjb25zdCBmaW5WaXNpYmxlID0gbmV3IERhdGUoMjAyNiwgMCwgNSk7IGZpblZpc2libGUuc2V0RGF0ZShmaW5WaXNpYmxlLmdldERhdGUoKSArIFlFQVIgLSAxKTsKICAgIGV4cGVjdChmZWNoYUVuUmFuZ28oIjIwMjYtMDEtMDUiLCByYW5nbykpLnRvQmUodHJ1ZSk7IC8vIHByaW1lciBkw61hIHZpc2libGUKICAgIGV4cGVjdChmZWNoYUVuUmFuZ28odG9EUyhmaW5WaXNpYmxlKSwgcmFuZ28pKS50b0JlKHRydWUpOyAvLyDDumx0aW1vIGTDrWEgdmlzaWJsZQogIH0pOwoKICBpdCgiZWwgcmFuZ28gZGVwZW5kZSB0YW50byBkZSBzdGFydERhdGUgY29tbyBkZWwgbsO6bWVybyBkZSBkw61hcyB2aXNpYmxlcyAodmlld01vZGUpIiwgKCkgPT4gewogICAgY29uc3QgcmFuZ29TZW1hbmEgPSBnZXRSYW5nb0ZldGNoQXNpZ25hY2lvbmVzKG5ldyBEYXRlKDIwMjYsIDYsIDYpLCBXRUVLKTsKICAgIGNvbnN0IHJhbmdvTWVzID0gZ2V0UmFuZ29GZXRjaEFzaWduYWNpb25lcyhuZXcgRGF0ZSgyMDI2LCA2LCA2KSwgTU9OVEgpOwogICAgZXhwZWN0KHJhbmdvTWVzLnRvRHMgPiByYW5nb1NlbWFuYS50b0RzKS50b0JlKHRydWUpOyAvLyB2aXN0YSBtZXMgcGlkZSBtw6FzIGTDrWFzIGhhY2lhIGFkZWxhbnRlIHF1ZSB2aXN0YSBzZW1hbmEKICB9KTsKCiAgaXQoImZlY2hhRW5SYW5nbyBlcyBpbmNsdXNpdm8gZW4gYW1ib3MgZXh0cmVtb3MiLCAoKSA9PiB7CiAgICBjb25zdCByYW5nbyA9IHsgZnJvbURzOiAiMjAyNi0wNy0wMSIsIHRvRHM6ICIyMDI2LTA3LTMxIiB9OwogICAgZXhwZWN0KGZlY2hhRW5SYW5nbygiMjAyNi0wNy0wMSIsIHJhbmdvKSkudG9CZSh0cnVlKTsKICAgIGV4cGVjdChmZWNoYUVuUmFuZ28oIjIwMjYtMDctMzEiLCByYW5nbykpLnRvQmUodHJ1ZSk7CiAgICBleHBlY3QoZmVjaGFFblJhbmdvKCIyMDI2LTA2LTMwIiwgcmFuZ28pKS50b0JlKGZhbHNlKTsKICAgIGV4cGVjdChmZWNoYUVuUmFuZ28oIjIwMjYtMDgtMDEiLCByYW5nbykpLnRvQmUoZmFsc2UpOwogIH0pOwp9KTsKCmZ1bmN0aW9uIHRvRFMoZDogRGF0ZSk6IHN0cmluZyB7CiAgcmV0dXJuIGAke2QuZ2V0RnVsbFllYXIoKX0tJHtTdHJpbmcoZC5nZXRNb250aCgpICsgMSkucGFkU3RhcnQoMiwgIjAiKX0tJHtTdHJpbmcoZC5nZXREYXRlKCkpLnBhZFN0YXJ0KDIsICIwIil9YDsKfQo=
"@
$bytes_src_lib_utils_planificadorRango_test_ts = [System.Convert]::FromBase64String($b64_src_lib_utils_planificadorRango_test_ts)
$dest_src_lib_utils_planificadorRango_test_ts = Join-Path $RepoPath "src\lib\utils\planificadorRango.test.ts"
$dir_src_lib_utils_planificadorRango_test_ts = Split-Path $dest_src_lib_utils_planificadorRango_test_ts -Parent
if (!(Test-Path $dir_src_lib_utils_planificadorRango_test_ts)) { New-Item -ItemType Directory -Force -Path $dir_src_lib_utils_planificadorRango_test_ts | Out-Null }
[System.IO.File]::WriteAllBytes($dest_src_lib_utils_planificadorRango_test_ts, $bytes_src_lib_utils_planificadorRango_test_ts)
$size_src_lib_utils_planificadorRango_test_ts = (Get-Item $dest_src_lib_utils_planificadorRango_test_ts).Length
Write-Host "   src/lib/utils/planificadorRango.test.ts: $size_src_lib_utils_planificadorRango_test_ts bytes escritos (esperado 6989) en $($dest_src_lib_utils_planificadorRango_test_ts)" -ForegroundColor Green
if ($size_src_lib_utils_planificadorRango_test_ts -ne 6989) { Write-Host "   ERROR: tamano no coincide para src/lib/utils/planificadorRango.test.ts" -ForegroundColor Red; exit 1 }

# ----------------------------------------------------------------------------
# vitest.config.mts
# Archivo que tambien faltaba en GitHub. Configuracion minima de Vitest.
# SHA256 original: 8630c92962698a265c754ed07f531a83d527c38a5c0f9598c228259ae1e3fe36
# ----------------------------------------------------------------------------
Write-Host "== Escribiendo vitest.config.mts ==" -ForegroundColor Cyan
$b64_vitest_config_mts = @"
aW1wb3J0IHsgZGVmaW5lQ29uZmlnIH0gZnJvbSAidml0ZXN0L2NvbmZpZyI7CgovLyBDb25maWcgbWluaW1hOiBwb3IgYWhvcmEgbGFzIHBydWViYXMgY3VicmVuIGxvZ2ljYSBwdXJhIChzaW4gRE9NL1JlYWN0KSwKLy8gYXNpIHF1ZSBubyBoYWNlIGZhbHRhIGpzZG9tIG5pIHJlc29sdmVyIGVsIGFsaWFzICJALy4uLiIgZGUgdHNjb25maWcuCi8vIFNpIGVuIGVsIGZ1dHVybyBzZSBhw7FhZGVuIHRlc3RzIGRlIGNvbXBvbmVudGVzLCBhbXBsaWFyIGFxdWkKLy8gKGVudmlyb25tZW50OiAianNkb20iICsgcmVzb2x2ZS5hbGlhcyAiQCIgLT4gIi4vc3JjIikuCmV4cG9ydCBkZWZhdWx0IGRlZmluZUNvbmZpZyh7CiAgdGVzdDogewogICAgZW52aXJvbm1lbnQ6ICJub2RlIiwKICAgIGluY2x1ZGU6IFsic3JjLyoqLyoudGVzdC50cyJdLAogIH0sCn0pOwo=
"@
$bytes_vitest_config_mts = [System.Convert]::FromBase64String($b64_vitest_config_mts)
$dest_vitest_config_mts = Join-Path $RepoPath "vitest.config.mts"
$dir_vitest_config_mts = Split-Path $dest_vitest_config_mts -Parent
if (!(Test-Path $dir_vitest_config_mts)) { New-Item -ItemType Directory -Force -Path $dir_vitest_config_mts | Out-Null }
[System.IO.File]::WriteAllBytes($dest_vitest_config_mts, $bytes_vitest_config_mts)
$size_vitest_config_mts = (Get-Item $dest_vitest_config_mts).Length
Write-Host "   vitest.config.mts: $size_vitest_config_mts bytes escritos (esperado 428) en $($dest_vitest_config_mts)" -ForegroundColor Green
if ($size_vitest_config_mts -ne 428) { Write-Host "   ERROR: tamano no coincide para vitest.config.mts" -ForegroundColor Red; exit 1 }

# ----------------------------------------------------------------------------
# package.json
# Se reescribe entero: le faltaban en GitHub los scripts "test"/"test:watch" y la devDependency vitest (el resto del archivo es identico al que ya hay en GitHub). IMPORTANTE: tras aplicar este script hay que ejecutar `npm install` una vez.
# SHA256 original: cc36d82791c26295a4969a65e448dd69f26032e7469eeb89a2e64948b952f008
# ----------------------------------------------------------------------------
Write-Host "== Escribiendo package.json ==" -ForegroundColor Cyan
$b64_package_json = @"
ewogICJuYW1lIjogIm9icmFzcGxhbiIsCiAgInZlcnNpb24iOiAiMC4xLjAiLAogICJwcml2YXRlIjogdHJ1ZSwKICAic2NyaXB0cyI6IHsKICAgICJkZXYiOiAibmV4dCBkZXYiLAogICAgImJ1aWxkIjogIm5leHQgYnVpbGQiLAogICAgInN0YXJ0IjogIm5leHQgc3RhcnQiLAogICAgImxpbnQiOiAibmV4dCBsaW50IiwKICAgICJkYjpzdGFydCI6ICJzdXBhYmFzZSBzdGFydCIsCiAgICAiZGI6c3RvcCI6ICJzdXBhYmFzZSBzdG9wIiwKICAgICJkYjpyZXNldCI6ICJzdXBhYmFzZSBkYiByZXNldCIsCiAgICAiZGI6bWlncmF0ZSI6ICJzdXBhYmFzZSBtaWdyYXRpb24gbmV3IiwKICAgICJkYjp0eXBlcyI6ICJzdXBhYmFzZSBnZW4gdHlwZXMgdHlwZXNjcmlwdCAtLWxvY2FsID4gc3JjL2xpYi90eXBlcy9kYXRhYmFzZS50cyIsCiAgICAidGVzdCI6ICJ2aXRlc3QgcnVuIiwKICAgICJ0ZXN0OndhdGNoIjogInZpdGVzdCIKICB9LAogICJkZXBlbmRlbmNpZXMiOiB7CiAgICAiQGRuZC1raXQvY29yZSI6ICJeNi4xLjAiLAogICAgIkBkbmQta2l0L3NvcnRhYmxlIjogIl44LjAuMCIsCiAgICAiQGRuZC1raXQvdXRpbGl0aWVzIjogIl4zLjIuMiIsCiAgICAiQHJhZGl4LXVpL3JlYWN0LWFsZXJ0LWRpYWxvZyI6ICJeMS4xLjIiLAogICAgIkByYWRpeC11aS9yZWFjdC1hdmF0YXIiOiAiXjEuMS4xIiwKICAgICJAcmFkaXgtdWkvcmVhY3QtY2hlY2tib3giOiAiXjEuMS4yIiwKICAgICJAcmFkaXgtdWkvcmVhY3QtZGlhbG9nIjogIl4xLjEuMiIsCiAgICAiQHJhZGl4LXVpL3JlYWN0LWRyb3Bkb3duLW1lbnUiOiAiXjIuMS4yIiwKICAgICJAcmFkaXgtdWkvcmVhY3QtbGFiZWwiOiAiXjIuMS4wIiwKICAgICJAcmFkaXgtdWkvcmVhY3QtcG9wb3ZlciI6ICJeMS4xLjIiLAogICAgIkByYWRpeC11aS9yZWFjdC1zZWxlY3QiOiAiXjIuMS4yIiwKICAgICJAcmFkaXgtdWkvcmVhY3Qtc2VwYXJhdG9yIjogIl4xLjEuMCIsCiAgICAiQHJhZGl4LXVpL3JlYWN0LXNsb3QiOiAiXjEuMS4wIiwKICAgICJAcmFkaXgtdWkvcmVhY3QtdGFicyI6ICJeMS4xLjEiLAogICAgIkByYWRpeC11aS9yZWFjdC10b2FzdCI6ICJeMS4yLjIiLAogICAgIkByYWRpeC11aS9yZWFjdC10b29sdGlwIjogIl4xLjEuMyIsCiAgICAiQHN1cGFiYXNlL3NzciI6ICJeMC41LjIiLAogICAgIkBzdXBhYmFzZS9zdXBhYmFzZS1qcyI6ICJeMi40Ny4xMCIsCiAgICAiQHRhbnN0YWNrL3JlYWN0LXF1ZXJ5IjogIl41LjYyLjAiLAogICAgIkB0YW5zdGFjay9yZWFjdC10YWJsZSI6ICJeOC4yMC41IiwKICAgICJAdHlwZXMvcXJjb2RlIjogIl4xLjUuNiIsCiAgICAiY2xhc3MtdmFyaWFuY2UtYXV0aG9yaXR5IjogIl4wLjcuMSIsCiAgICAiY2xzeCI6ICJeMi4xLjEiLAogICAgImRhdGUtZm5zIjogIl40LjEuMCIsCiAgICAiZGF0ZS1mbnMtdHoiOiAiXjMuMi4wIiwKICAgICJkb2N4IjogIl45LjcuMSIsCiAgICAianNwZGYiOiAiXjIuNS4yIiwKICAgICJqc3BkZi1hdXRvdGFibGUiOiAiXjMuOC4zIiwKICAgICJsZWFmbGV0IjogIl4xLjkuNCIsCiAgICAibHVjaWRlLXJlYWN0IjogIl4wLjQ2Mi4wIiwKICAgICJuZXh0IjogIjE0LjIuMTgiLAogICAgInFyY29kZSI6ICJeMS41LjQiLAogICAgInJlYWN0IjogIl4xOC4zLjEiLAogICAgInJlYWN0LWRvbSI6ICJeMTguMy4xIiwKICAgICJyZWFjdC1zaWduYXR1cmUtY2FudmFzIjogIl4xLjAuNiIsCiAgICAicmVzZW5kIjogIl40LjguMCIsCiAgICAidGFpbHdpbmQtbWVyZ2UiOiAiXjIuNi4wIiwKICAgICJ0YWlsd2luZGNzcy1hbmltYXRlIjogIl4xLjAuNyIsCiAgICAieGxzeCI6ICJeMC4xOC41IiwKICAgICJ6dXN0YW5kIjogIl41LjAuMiIKICB9LAogICJkZXZEZXBlbmRlbmNpZXMiOiB7CiAgICAiQHR5cGVzL2xlYWZsZXQiOiAiXjEuOS4yMSIsCiAgICAiQHR5cGVzL25vZGUiOiAiXjIyLjEwLjAiLAogICAgIkB0eXBlcy9yZWFjdCI6ICJeMTguMy4xMiIsCiAgICAiQHR5cGVzL3JlYWN0LWRvbSI6ICJeMTguMy4xIiwKICAgICJAdHlwZXMvcmVhY3Qtc2lnbmF0dXJlLWNhbnZhcyI6ICJeMS4wLjUiLAogICAgImF1dG9wcmVmaXhlciI6ICJeMTAuNC4yMCIsCiAgICAiZXNsaW50IjogIl44LjU3LjAiLAogICAgImVzbGludC1jb25maWctbmV4dCI6ICIxNC4yLjE4IiwKICAgICJwb3N0Y3NzIjogIl44LjQuNDkiLAogICAgInN1cGFiYXNlIjogIl4yLjAuMCIsCiAgICAidGFpbHdpbmRjc3MiOiAiXjMuNC4xNiIsCiAgICAidHlwZXNjcmlwdCI6ICJeNS43LjIiLAogICAgInZpdGVzdCI6ICJeNS4wLjAiCiAgfQp9Cg==
"@
$bytes_package_json = [System.Convert]::FromBase64String($b64_package_json)
$dest_package_json = Join-Path $RepoPath "package.json"
$dir_package_json = Split-Path $dest_package_json -Parent
if (!(Test-Path $dir_package_json)) { New-Item -ItemType Directory -Force -Path $dir_package_json | Out-Null }
[System.IO.File]::WriteAllBytes($dest_package_json, $bytes_package_json)
$size_package_json = (Get-Item $dest_package_json).Length
Write-Host "   package.json: $size_package_json bytes escritos (esperado 2284) en $($dest_package_json)" -ForegroundColor Green
if ($size_package_json -ne 2284) { Write-Host "   ERROR: tamano no coincide para package.json" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "== Verificacion de contenido clave ==" -ForegroundColor Cyan

$content_src_lib_utils_planificadorRango_ts = Get-Content -Raw (Join-Path $RepoPath "src\lib\utils\planificadorRango.ts")
if ($content_src_lib_utils_planificadorRango_ts.Contains("export function getRangoFetchAsignaciones(")) { Write-Host "   OK  src/lib/utils/planificadorRango.ts contiene: export function getRangoFetchAsignaciones(" -ForegroundColor Green } else { Write-Host "   FALTA en src/lib/utils/planificadorRango.ts: export function getRangoFetchAsignaciones(" -ForegroundColor Red; exit 1 }
if ($content_src_lib_utils_planificadorRango_ts.Contains("export function asignacionSolapaRango(")) { Write-Host "   OK  src/lib/utils/planificadorRango.ts contiene: export function asignacionSolapaRango(" -ForegroundColor Green } else { Write-Host "   FALTA en src/lib/utils/planificadorRango.ts: export function asignacionSolapaRango(" -ForegroundColor Red; exit 1 }
if ($content_src_lib_utils_planificadorRango_ts.Contains("export function fechaEnRango(")) { Write-Host "   OK  src/lib/utils/planificadorRango.ts contiene: export function fechaEnRango(" -ForegroundColor Green } else { Write-Host "   FALTA en src/lib/utils/planificadorRango.ts: export function fechaEnRango(" -ForegroundColor Red; exit 1 }

$content_src_lib_utils_planificadorRango_test_ts = Get-Content -Raw (Join-Path $RepoPath "src\lib\utils\planificadorRango.test.ts")
if ($content_src_lib_utils_planificadorRango_test_ts.Contains("it(`"Test 1: una asignaci")) { Write-Host "   OK  src/lib/utils/planificadorRango.test.ts contiene: it(`"Test 1: una asignaci" -ForegroundColor Green } else { Write-Host "   FALTA en src/lib/utils/planificadorRango.test.ts: it(`"Test 1: una asignaci" -ForegroundColor Red; exit 1 }
if ($content_src_lib_utils_planificadorRango_test_ts.Contains("it(`"Test 5: navegar julio")) { Write-Host "   OK  src/lib/utils/planificadorRango.test.ts contiene: it(`"Test 5: navegar julio" -ForegroundColor Green } else { Write-Host "   FALTA en src/lib/utils/planificadorRango.test.ts: it(`"Test 5: navegar julio" -ForegroundColor Red; exit 1 }
if ($content_src_lib_utils_planificadorRango_test_ts.Contains("import { asignacionSolapaRango, fechaEnRango, getRangoFetchAsignaciones } from `"./planificadorRango`";")) { Write-Host "   OK  src/lib/utils/planificadorRango.test.ts contiene: import { asignacionSolapaRango, fechaEnRango, getRangoFetchA" -ForegroundColor Green } else { Write-Host "   FALTA en src/lib/utils/planificadorRango.test.ts: import { asignacionSolapaRango, fechaEnRango, getRangoFetchA" -ForegroundColor Red; exit 1 }

$content_vitest_config_mts = Get-Content -Raw (Join-Path $RepoPath "vitest.config.mts")
if ($content_vitest_config_mts.Contains("include: [`"src/**/*.test.ts`"]")) { Write-Host "   OK  vitest.config.mts contiene: include: [`"src/**/*.test.ts`"]" -ForegroundColor Green } else { Write-Host "   FALTA en vitest.config.mts: include: [`"src/**/*.test.ts`"]" -ForegroundColor Red; exit 1 }

$content_package_json = Get-Content -Raw (Join-Path $RepoPath "package.json")
if ($content_package_json.Contains("`"test`": `"vitest run`"")) { Write-Host "   OK  package.json contiene: `"test`": `"vitest run`"" -ForegroundColor Green } else { Write-Host "   FALTA en package.json: `"test`": `"vitest run`"" -ForegroundColor Red; exit 1 }
if ($content_package_json.Contains("`"vitest`": `"^5.0.0`"")) { Write-Host "   OK  package.json contiene: `"vitest`": `"^5.0.0`"" -ForegroundColor Green } else { Write-Host "   FALTA en package.json: `"vitest`": `"^5.0.0`"" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "== git status (antes de add, para que veas exactamente que se va a subir) ==" -ForegroundColor Cyan
git status --short

Write-Host ""
Write-Host "== git add / commit / push ==" -ForegroundColor Cyan
git add -A
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git add -A ha fallado (codigo $LASTEXITCODE). El script se detiene aqui." -ForegroundColor Red; exit 1 }

git status --short
Write-Host "(el listado de arriba son los archivos que se van a confirmar - deberian ser los 4 de este script)" -ForegroundColor Cyan

git commit -m "fix: anadir planificadorRango.ts y vitest que faltaban en GitHub (build roto en Vercel)"
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git commit ha fallado (codigo $LASTEXITCODE). Puede que no haya nada que confirmar (los archivos ya estaban subidos) - revisa el mensaje de arriba. El script se detiene aqui." -ForegroundColor Red; exit 1 }

git push
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: git push ha fallado (codigo $LASTEXITCODE). El commit se ha creado EN LOCAL pero NO ha llegado a GitHub todavia - vuelve a intentar 'git push' a mano y pega aqui el mensaje de error si persiste. El script se detiene aqui." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "== Verificacion final: confirmando que GitHub tiene ya el ultimo commit ==" -ForegroundColor Cyan
git fetch origin main
$localHead = git rev-parse HEAD
$remoteHead = git rev-parse origin/main
Write-Host "   HEAD local:  $localHead" -ForegroundColor Cyan
Write-Host "   origin/main: $remoteHead" -ForegroundColor Cyan
if ($localHead -ne $remoteHead) { Write-Host "ERROR: el push parece haber terminado sin error pero origin/main no coincide con tu HEAD local. Avisa antes de dar esto por resuelto." -ForegroundColor Red; exit 1 }
Write-Host "   OK: GitHub tiene exactamente este commit." -ForegroundColor Green

Write-Host ""
Write-Host "== RECORDATORIOS ==" -ForegroundColor Yellow
Write-Host "1) Ejecuta 'npm install' una vez (se ha anadido vitest como devDependency)." -ForegroundColor Yellow
Write-Host "2) Opcional: 'npm test' deberia mostrar 17 pruebas en verde (9 + 8)." -ForegroundColor Yellow
Write-Host "3) En Vercel deberia lanzarse un nuevo deployment solo. Cuando termine en verde, PROMOCIONALO MANUALMENTE a produccion: Deployments -> menu ... -> Promote to Production (Vercel Hobby no lo hace solo)." -ForegroundColor Yellow
Write-Host "4) No hay migraciones SQL que aplicar en Supabase para este cambio." -ForegroundColor Yellow
Write-Host ""
Write-Host "Script completado correctamente." -ForegroundColor Green
