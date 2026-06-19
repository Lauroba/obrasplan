#Requires -Version 5.1
<#
  fix-menu-aplicaciones.ps1
  ---------------------------
  Correccion dirigida: el script de despliegue anterior no logro copiar
  correctamente 5 archivos del modulo Aplicaciones/Georadar (quedaron con
  el nombre del zip en vez de renombrarse a su destino real, o no se
  sobrescribieron). Este script coloca exactamente esos 5 archivos en su
  sitio correcto, verificando antes y despues de cada copia.

  Archivos que corrige:
    - src/components/layout/Sidebar.tsx       (anade el grupo Aplicaciones)
    - src/hooks/usePermissions.ts              (anade apps_georadar para admin)
    - src/hooks/useRouteGuard.ts                (anade la ruta /aplicaciones/georadar)
    - src/app/aplicaciones/page.tsx             (pagina catalogo, antes mal nombrada)
    - src/app/aplicaciones/georadar/page.tsx    (pagina app, antes mal nombrada)

  Uso:
    .\fix-menu-aplicaciones.ps1
#>

[CmdletBinding()]
param(
    [string]$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan",
    [string]$ZipPath = ""
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "" ; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "    ERROR: $msg" -ForegroundColor Red }

Write-Step "Comprobando entorno"

if (-not (Test-Path $RepoPath)) {
    Write-Err "No se encuentra la carpeta del repo: $RepoPath"
    exit 1
}
Write-Ok "Repo: $RepoPath"

if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $candidatos = Get-ChildItem -Path $scriptDir -Filter "*.zip" -File -ErrorAction SilentlyContinue
    if ($candidatos.Count -eq 0) {
        Write-Err "No se encontro ningun .zip en la carpeta del script: $scriptDir"
        Write-Err "Coloca el zip fix-menu-aplicaciones.zip en la misma carpeta que este script."
        exit 1
    }
    $ZipPath = $candidatos[0].FullName
}
Write-Ok "Zip: $ZipPath"

Write-Step "Descomprimiendo"
$tempDir = Join-Path $env:TEMP ("georadar-fix-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tempDir | Out-Null
Expand-Archive -Path $ZipPath -DestinationPath $tempDir -Force
Write-Ok "Extraido en: $tempDir"

# -----------------------------------------------------------------------
# Mapa de copia: origen en el zip (carpeta files\) -> destino real
# -----------------------------------------------------------------------
$copyMap = @(
    @{ Src = "files\Sidebar.tsx";          Dst = "src\components\layout\Sidebar.tsx" }
    @{ Src = "files\usePermissions.ts";    Dst = "src\hooks\usePermissions.ts" }
    @{ Src = "files\useRouteGuard.ts";     Dst = "src\hooks\useRouteGuard.ts" }
    @{ Src = "files\page-aplicaciones.tsx"; Dst = "src\app\aplicaciones\page.tsx" }
    @{ Src = "files\page-georadar.tsx";     Dst = "src\app\aplicaciones\georadar\page.tsx" }
)

$backupDir = Join-Path $RepoPath (".georadar-fix-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$backedUp = $false
$allOk = $true

Write-Step "Verificando estado ANTES de corregir"
foreach ($item in $copyMap) {
    $dstFull = Join-Path $RepoPath $item.Dst
    if (Test-Path $dstFull) {
        $hasMarker = Select-String -Path $dstFull -Pattern "apps_georadar|georadar|Aplicaciones" -Quiet -ErrorAction SilentlyContinue
        if ($hasMarker) {
            Write-Ok ("Ya contiene georadar: " + $item.Dst)
        } else {
            Write-Warn ("Existe pero SIN georadar (version vieja): " + $item.Dst)
        }
    } else {
        Write-Warn ("No existe todavia: " + $item.Dst)
    }
}

Write-Step "Copiando archivos correctos a su destino real"
foreach ($item in $copyMap) {
    $srcFull = Join-Path $tempDir $item.Src
    $dstFull = Join-Path $RepoPath $item.Dst

    if (-not (Test-Path $srcFull)) {
        Write-Err ("Falta en el zip: " + $item.Src)
        $allOk = $false
        continue
    }

    $dstDir = Split-Path -Parent $dstFull
    if (-not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    if (Test-Path $dstFull) {
        if (-not $backedUp) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            $backedUp = $true
        }
        $backupTarget = Join-Path $backupDir $item.Dst
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupTarget) -Force | Out-Null
        Copy-Item -Path $dstFull -Destination $backupTarget -Force
    }

    Copy-Item -Path $srcFull -Destination $dstFull -Force
    Write-Ok ("Copiado: " + $item.Dst)
}

Write-Step "Verificando estado DESPUES de corregir"
foreach ($item in $copyMap) {
    $dstFull = Join-Path $RepoPath $item.Dst
    if (Test-Path $dstFull) {
        $hasMarker = Select-String -Path $dstFull -Pattern "apps_georadar|georadar|Aplicaciones" -Quiet -ErrorAction SilentlyContinue
        if ($hasMarker) {
            Write-Ok ("Confirmado correcto: " + $item.Dst)
        } else {
            Write-Err ("SIGUE SIN georadar tras la copia: " + $item.Dst)
            $allOk = $false
        }
    } else {
        Write-Err ("SIGUE SIN EXISTIR: " + $item.Dst)
        $allOk = $false
    }
}

# Limpieza de los archivos viejos mal nombrados, si existen
$staleFiles = @(
    "src\app\aplicaciones\aplicaciones-page.tsx",
    "src\app\aplicaciones\georadar\georadar-page.tsx"
)
Write-Step "Limpiando archivos mal nombrados del intento anterior (si existen)"
foreach ($stale in $staleFiles) {
    $staleFull = Join-Path $RepoPath $stale
    if (Test-Path $staleFull) {
        Remove-Item -Path $staleFull -Force
        Write-Ok ("Eliminado archivo mal nombrado: " + $stale)
    }
}

Write-Step "Resultado"
if ($allOk) {
    Write-Host ""
    Write-Host "  Los 5 archivos quedaron en su sitio correcto." -ForegroundColor Green
    if ($backedUp) {
        Write-Host ("  Backup de lo sobrescrito en: " + $backupDir)
    }
    Write-Host ""
    Write-Host "  Siguiente paso:"
    Write-Host "    git add ."
    Write-Host "    git commit -m `"fix: completar integracion de menu Aplicaciones (Sidebar/permisos/paginas)`""
    Write-Host "    git push"
    Write-Host ""
    Write-Host "  Despues, promociona manualmente en el dashboard de Vercel."
} else {
    Write-Host ""
    Write-Host "  Algo no quedo bien. Revisa los ERROR de arriba antes de hacer commit." -ForegroundColor Red
}

Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
