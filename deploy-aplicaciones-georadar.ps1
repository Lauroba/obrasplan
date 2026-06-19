#Requires -Version 5.1
<#
  deploy-aplicaciones-georadar.ps1
  ---------------------------------
  Despliega en local el modulo Aplicaciones + app Interpretacion de
  Georradar (migracion 028 + motor de deteccion + paginas + endpoints +
  integracion de menu y permisos).

  Que hace, en orden:
    1. Localiza el zip de la entrega (misma carpeta que este script, o
       ruta indicada con -ZipPath).
    2. Descomprime a una carpeta temporal.
    3. Copia cada archivo a su destino final dentro del repo, renombrando
       los que chocan de nombre con archivos existentes (Sidebar.tsx,
       usePermissions.ts, useRouteGuard.ts, las paginas page.tsx).
    4. Hace backup de cualquier archivo que vaya a sobrescribir.
    5. Anade la dependencia "docx" a package.json por sustitucion de
       texto exacta (detecta si ya esta aplicado).
    6. Ejecuta npm install para instalar la dependencia nueva.
    7. Muestra un resumen y, opcionalmente, ejecuta git add/commit/push
       si confirmas con -GitCommit.

  Uso (ya dentro de PowerShell):
    .\deploy-aplicaciones-georadar.ps1

  Parametros opcionales:
    -RepoPath   Ruta raiz del repo (por defecto, la ruta conocida del proyecto)
    -ZipPath    Ruta al zip descargado (por defecto, busca *.zip en la carpeta del script)
    -GitCommit  Si se pasa, hace git add + commit + push al final (pide confirmacion igualmente)
    -SkipNpm    Si se pasa, no ejecuta npm install (por si prefieres hacerlo tu mismo)
#>

[CmdletBinding()]
param(
    [string]$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan",
    [string]$ZipPath = "",
    [switch]$GitCommit,
    [switch]$SkipNpm
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "" ; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "    ERROR: $msg" -ForegroundColor Red }

# -----------------------------------------------------------------------
# 0. Validaciones previas
# -----------------------------------------------------------------------
Write-Step "Comprobando entorno"

if (-not (Test-Path $RepoPath)) {
    Write-Err "No se encuentra la carpeta del repo: $RepoPath"
    Write-Err "Ejecuta el script con -RepoPath y la ruta correcta si tu proyecto esta en otro sitio."
    exit 1
}
if (-not (Test-Path (Join-Path $RepoPath "package.json"))) {
    Write-Err "La carpeta indicada no parece la raiz del proyecto (falta package.json): $RepoPath"
    exit 1
}
Write-Ok "Repo encontrado: $RepoPath"

if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $candidatos = Get-ChildItem -Path $scriptDir -Filter "obrasplan-aplicaciones-georadar*.zip" -File -ErrorAction SilentlyContinue
    if ($candidatos.Count -eq 0) {
        $candidatos = Get-ChildItem -Path $scriptDir -Filter "*.zip" -File -ErrorAction SilentlyContinue
    }
    if ($candidatos.Count -eq 0) {
        Write-Err "No se encontro ningun .zip en la carpeta del script: $scriptDir"
        Write-Err "Coloca el zip de la entrega en la misma carpeta que este script, o pasa -ZipPath con la ruta al zip."
        exit 1
    }
    $ZipPath = $candidatos[0].FullName
}
if (-not (Test-Path $ZipPath)) {
    Write-Err "No se encuentra el zip indicado: $ZipPath"
    exit 1
}
Write-Ok "Zip de entrega: $ZipPath"

# -----------------------------------------------------------------------
# 1. Descomprimir a carpeta temporal
# -----------------------------------------------------------------------
Write-Step "Descomprimiendo paquete"

$tempDir = Join-Path $env:TEMP ("obrasplan-georadar-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tempDir | Out-Null
Expand-Archive -Path $ZipPath -DestinationPath $tempDir -Force
Write-Ok "Extraido en: $tempDir"

# -----------------------------------------------------------------------
# 2. Mapa de copia: origen relativo al zip -> destino relativo al repo
#    (incluye los renombres necesarios)
# -----------------------------------------------------------------------
$copyMap = @(
    @{ Src = "supabase\migrations\028_aplicaciones_georadar.sql";          Dst = "supabase\migrations\028_aplicaciones_georadar.sql" }
    @{ Src = "src\lib\georadar\parseSegy.ts";                              Dst = "src\lib\georadar\parseSegy.ts" }
    @{ Src = "src\lib\georadar\detectAnomalies.ts";                        Dst = "src\lib\georadar\detectAnomalies.ts" }
    @{ Src = "src\lib\georadar\genDemo.ts";                                Dst = "src\lib\georadar\genDemo.ts" }
    @{ Src = "src\lib\georadar\parseGnss.ts";                              Dst = "src\lib\georadar\parseGnss.ts" }
    @{ Src = "src\lib\georadar\renderRadargram.ts";                        Dst = "src\lib\georadar\renderRadargram.ts" }
    @{ Src = "src\lib\georadar\buildPrompt.ts";                            Dst = "src\lib\georadar\buildPrompt.ts" }
    @{ Src = "src\lib\georadar\generateInformeDocx.ts";                    Dst = "src\lib\georadar\generateInformeDocx.ts" }
    @{ Src = "src\lib\georadar\useGeoradarStore.ts";                       Dst = "src\lib\georadar\useGeoradarStore.ts" }
    @{ Src = "src\app\api\aplicaciones\georadar\analizar\route.ts";        Dst = "src\app\api\aplicaciones\georadar\analizar\route.ts" }
    @{ Src = "src\app\api\aplicaciones\georadar\informe\route.ts";         Dst = "src\app\api\aplicaciones\georadar\informe\route.ts" }
    @{ Src = "src\app\aplicaciones\aplicaciones-page.tsx";                 Dst = "src\app\aplicaciones\page.tsx" }
    @{ Src = "src\app\aplicaciones\georadar\georadar-page.tsx";            Dst = "src\app\aplicaciones\georadar\page.tsx" }
    @{ Src = "src\components\layout\sidebar-georadar.tsx";                 Dst = "src\components\layout\Sidebar.tsx" }
    @{ Src = "src\hooks\usepermissions-georadar.ts";                       Dst = "src\hooks\usePermissions.ts" }
    @{ Src = "src\hooks\userouteguard-georadar.ts";                        Dst = "src\hooks\useRouteGuard.ts" }
)

Write-Step "Copiando archivos al repo (con backup de lo existente)"

$backupDir = Join-Path $RepoPath (".georadar-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$backedUp = $false

foreach ($item in $copyMap) {
    $srcFull = Join-Path $tempDir $item.Src
    $dstFull = Join-Path $RepoPath $item.Dst

    if (-not (Test-Path $srcFull)) {
        Write-Err ("Falta en el zip: " + $item.Src)
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
        Write-Warn ("Sobrescrito (backup en .georadar-backup-*): " + $item.Dst)
    } else {
        Write-Ok ("Nuevo archivo: " + $item.Dst)
    }

    Copy-Item -Path $srcFull -Destination $dstFull -Force
}

# -----------------------------------------------------------------------
# 3. Parchear package.json (anadir dependencia "docx")
# -----------------------------------------------------------------------
Write-Step "Anadiendo dependencia docx a package.json"

$pkgPath = Join-Path $RepoPath "package.json"

if (-not (Test-Path $pkgPath)) {
    Write-Err "No se encuentra package.json - omite este paso, aplicalo manualmente con PATCH_package_json.txt"
} else {
    $content = Get-Content -Path $pkgPath -Raw

    $oldBlock = @'
    "date-fns": "^4.1.0",
    "date-fns-tz": "^3.2.0",
    "jspdf": "^2.5.2",
'@

    $newBlock = @'
    "date-fns": "^4.1.0",
    "date-fns-tz": "^3.2.0",
    "docx": "^9.7.1",
    "jspdf": "^2.5.2",
'@

    $normalizedContent = $content -replace "`r`n", "`n"
    $normalizedOld = $oldBlock -replace "`r`n", "`n"
    $normalizedNew = $newBlock -replace "`r`n", "`n"

    $marker = '"docx":'

    if ($normalizedContent -match [regex]::Escape($marker)) {
        Write-Warn "La dependencia docx ya parece estar en package.json. No se modifica."
    }
    elseif ($normalizedContent.Contains($normalizedOld)) {
        if (-not $backedUp) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            $backedUp = $true
        }
        $backupTarget = Join-Path $backupDir "package.json"
        Copy-Item -Path $pkgPath -Destination $backupTarget -Force

        $patched = $normalizedContent.Replace($normalizedOld, $normalizedNew)
        $patched = $patched -replace "`n", "`r`n"
        Set-Content -Path $pkgPath -Value $patched -NoNewline -Encoding UTF8
        Write-Ok "package.json actualizado (backup guardado)."
    }
    else {
        Write-Err "No se encontro el bloque esperado en package.json."
        Write-Err "El archivo pudo haber cambiado desde que se preparo este modulo."
        Write-Err "Aplica el cambio manualmente usando PATCH_package_json.txt (incluido en el zip)."
    }
}

# -----------------------------------------------------------------------
# 4. npm install
# -----------------------------------------------------------------------
if (-not $SkipNpm) {
    Write-Step "Instalando dependencias (npm install)"
    Push-Location $RepoPath
    try {
        npm install
        Write-Ok "Dependencias instaladas."
    } catch {
        Write-Err "Fallo npm install. Ejecutalo manualmente: npm install"
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  (Se omite npm install por -SkipNpm. Ejecuta 'npm install' manualmente.)" -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------
# 5. Resumen
# -----------------------------------------------------------------------
Write-Step "Resumen"

if ($backedUp) {
    $backupLine = "  Backups de lo sobrescrito en: " + $backupDir
} else {
    $backupLine = "  No hubo que sobrescribir nada (todo era nuevo)."
}

Write-Host ""
Write-Host ("  Archivos desplegados en: " + $RepoPath)
Write-Host $backupLine
Write-Host ""
Write-Host "  Pendiente fuera de este script (no automatizable sin acceso a tus paneles):"
Write-Host "    1) Ejecutar supabase\migrations\028_aplicaciones_georadar.sql en el"
Write-Host "       SQL Editor de Supabase (es idempotente, se puede reejecutar)."
Write-Host "    2) Anadir en Vercel las variables de entorno:"
Write-Host "       GEORADAR_ANTHROPIC_API_KEY  (clave de Anthropic de empresa)"
Write-Host "       GEORADAR_OPENAI_API_KEY     (clave de OpenAI de empresa)"
Write-Host "    3) IMPORTANTE: revocar la clave OpenAI que estaba en texto plano"
Write-Host "       dentro del HTML original (sk-proj-...), si no se ha hecho ya."
Write-Host "    4) Verificar build local: npm run build"
Write-Host "    5) Promocionar manualmente a produccion en el dashboard de Vercel"
Write-Host "       (plan Hobby no promociona automaticamente)."
Write-Host ""

# -----------------------------------------------------------------------
# 6. Git (opcional, requiere confirmacion explicita)
# -----------------------------------------------------------------------
if ($GitCommit) {
    Write-Step "Git add / commit / push"
    Push-Location $RepoPath
    try {
        git add .
        git status --short
        $confirm = Read-Host "Confirmas el commit y push de estos cambios? (s/n)"
        if ($confirm -eq "s") {
            git commit -m "feat: modulo Aplicaciones + app Interpretacion de Georradar (migracion + motor + permisos + auditoria)"
            git push
            Write-Ok "Cambios subidos a main."
        } else {
            Write-Warn "Commit cancelado. Los archivos ya estan en tu working tree, puedes revisarlos antes de subirlos."
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  (Para hacer commit y push automaticamente, vuelve a ejecutar con -GitCommit)" -ForegroundColor DarkGray
}

# Limpieza de la carpeta temporal
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
