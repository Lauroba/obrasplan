#Requires -Version 5.1
<#
  deploy-audit-fix.ps1
  --------------------
  Despliega en local el fix completo del sistema de auditoría de ObrasPlan
  (migración 026 + capa de log de errores + tipos_obra + logs page).

  Qué hace, en orden:
    1. Localiza el zip de la entrega (mismo directorio que este script, o
       ruta indicada con -ZipPath).
    2. Descomprime a una carpeta temporal.
    3. Copia cada archivo a su destino final dentro del repo, renombrando
       los dos que chocan de nombre (tipos-obra-page.tsx -> page.tsx,
       logs-page.tsx -> page.tsx), igual que se haría a mano.
    4. Hace backup (.bak) de cualquier archivo que vaya a sobrescribir.
    5. Aplica el patch de la interfaz AuditLog en
       src/lib/types/database.ts por sustitución de texto exacta (no edición
       manual). Si el bloque ya fue parcheado antes, lo detecta y no lo
       vuelve a tocar.
    6. Muestra un resumen y, opcionalmente, ejecuta git add/commit/push si
       confirmas con -GitCommit.

  Uso:
    powershell -ExecutionPolicy Bypass -File .\deploy-audit-fix.ps1

  Parámetros opcionales:
    -RepoPath   Ruta raíz del repo (por defecto, la ruta conocida del proyecto)
    -ZipPath    Ruta al zip descargado (por defecto, busca *.zip en la carpeta del script)
    -GitCommit  Si se pasa, hace git add + commit + push al final (pide confirmación igualmente)
#>

[CmdletBinding()]
param(
    [string]$RepoPath = "C:\Users\lauro\Desktop\LOYNEK\ObrasPlan\obrasplan-mvp\obrasplan",
    [string]$ZipPath = "",
    [switch]$GitCommit
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "    ERROR: $msg" -ForegroundColor Red }

# -----------------------------------------------------------------------
# 0. Validaciones previas
# -----------------------------------------------------------------------
Write-Step "Comprobando entorno"

if (-not (Test-Path $RepoPath)) {
    Write-Err "No se encuentra la carpeta del repo: $RepoPath"
    Write-Err "Ejecuta el script con -RepoPath 'ruta\correcta' si tu proyecto está en otro sitio."
    exit 1
}
if (-not (Test-Path (Join-Path $RepoPath "package.json"))) {
    Write-Err "La carpeta '$RepoPath' no parece la raíz del proyecto (falta package.json)."
    exit 1
}
Write-Ok "Repo encontrado: $RepoPath"

if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $candidatos = Get-ChildItem -Path $scriptDir -Filter "obrasplan-fix-auditoria*.zip" -File -ErrorAction SilentlyContinue
    if ($candidatos.Count -eq 0) {
        $candidatos = Get-ChildItem -Path $scriptDir -Filter "*.zip" -File -ErrorAction SilentlyContinue
    }
    if ($candidatos.Count -eq 0) {
        Write-Err "No se encontró ningún .zip en '$scriptDir'."
        Write-Err "Coloca el zip de la entrega en la misma carpeta que este script, o pasa -ZipPath 'ruta\al\zip'."
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

$tempDir = Join-Path $env:TEMP ("obrasplan-audit-fix-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $tempDir | Out-Null
Expand-Archive -Path $ZipPath -DestinationPath $tempDir -Force
Write-Ok "Extraído en: $tempDir"

# -----------------------------------------------------------------------
# 2. Mapa de copia: origen relativo al zip -> destino relativo al repo
#    (incluye los renombres necesarios)
# -----------------------------------------------------------------------
$copyMap = @(
    @{ Src = "supabase\migrations\026_audit_complete_fix.sql";              Dst = "supabase\migrations\026_audit_complete_fix.sql" }
    @{ Src = "src\lib\audit\logAuditError.ts";                              Dst = "src\lib\audit\logAuditError.ts" }
    @{ Src = "src\app\api\audit\log-error\route.ts";                        Dst = "src\app\api\audit\log-error\route.ts" }
    @{ Src = "src\app\maestros\tipos-obra\tipos-obra-page.tsx";             Dst = "src\app\maestros\tipos-obra\page.tsx" }
    @{ Src = "src\app\logs\logs-page.tsx";                                  Dst = "src\app\logs\page.tsx" }
)

Write-Step "Copiando archivos al repo (con backup de lo existente)"

$backupDir = Join-Path $RepoPath (".audit-fix-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$backedUp = $false

foreach ($item in $copyMap) {
    $srcFull = Join-Path $tempDir $item.Src
    $dstFull = Join-Path $RepoPath $item.Dst

    if (-not (Test-Path $srcFull)) {
        Write-Err "Falta en el zip: $($item.Src)"
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
        Write-Warn "Sobrescrito (backup en .audit-fix-backup-*): $($item.Dst)"
    } else {
        Write-Ok "Nuevo archivo: $($item.Dst)"
    }

    Copy-Item -Path $srcFull -Destination $dstFull -Force
}

# -----------------------------------------------------------------------
# 3. Parchear src/lib/types/database.ts (interfaz AuditLog)
# -----------------------------------------------------------------------
Write-Step "Parcheando src\lib\types\database.ts (interfaz AuditLog)"

$dbTypesPath = Join-Path $RepoPath "src\lib\types\database.ts"

if (-not (Test-Path $dbTypesPath)) {
    Write-Err "No se encuentra $dbTypesPath — omite este paso, aplícalo manualmente con PATCH_database_types.txt"
} else {
    $content = Get-Content -Path $dbTypesPath -Raw

    $oldBlock = @"
export interface AuditLog {
  id: string;
  user_id: string | null;
  accion: AuditAccion;
  entidad: string;
  entidad_id: string | null;
  valor_anterior: Record<string, unknown> | null;
  valor_nuevo: Record<string, unknown> | null;
  ip_address: string | null;
  user_agent: string | null;
  created_at: string;
  user?: User;
}
"@

    $newBlock = @"
export interface AuditLog {
  id: string;
  user_id: string | null;
  user_rol: string | null;
  accion: AuditAccion;
  entidad: string;
  entidad_id: string | null;
  modulo: string | null;
  descripcion: string | null;
  resultado: "exito" | "error";
  error_detalle: string | null;
  origen: "trigger_db" | "api_route" | "rpc_manual" | "client_catch";
  valor_anterior: Record<string, unknown> | null;
  valor_nuevo: Record<string, unknown> | null;
  ip_address: string | null;
  user_agent: string | null;
  created_at: string;
  user?: User;
}
"@

    # Normalizar saltos de línea para que la comparación de texto funcione
    # igual en Windows (CRLF) que en el contenido generado aquí (LF).
    $normalizedContent = $content -replace "`r`n", "`n"
    $normalizedOld = $oldBlock -replace "`r`n", "`n"
    $normalizedNew = $newBlock -replace "`r`n", "`n"

    if ($normalizedContent -match [regex]::Escape("user_rol: string | null;")) {
        Write-Warn "El patch ya parece aplicado (se encontró 'user_rol' en AuditLog). No se modifica."
    }
    elseif ($normalizedContent.Contains($normalizedOld)) {
        if (-not $backedUp) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            $backedUp = $true
        }
        $backupTarget = Join-Path $backupDir "src\lib\types\database.ts"
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupTarget) -Force | Out-Null
        Copy-Item -Path $dbTypesPath -Destination $backupTarget -Force

        $patched = $normalizedContent.Replace($normalizedOld, $normalizedNew)
        # Volver a CRLF para mantener consistencia con el resto del repo en Windows
        $patched = $patched -replace "`n", "`r`n"
        Set-Content -Path $dbTypesPath -Value $patched -NoNewline -Encoding UTF8
        Write-Ok "Interfaz AuditLog actualizada (backup guardado)."
    }
    else {
        Write-Err "No se encontró el bloque esperado de AuditLog en database.ts."
        Write-Err "El archivo pudo haber cambiado desde que se preparó este fix."
        Write-Err "Aplica el cambio manualmente usando PATCH_database_types.txt (incluido en el zip)."
    }
}

# -----------------------------------------------------------------------
# 4. Resumen
# -----------------------------------------------------------------------
Write-Step "Resumen"

Write-Host @"

  Archivos desplegados en: $RepoPath
  $(if ($backedUp) { "  Backups de lo sobrescrito en: $backupDir" } else { "  No hubo que sobrescribir nada (todo era nuevo)." })

  Pendiente fuera de este script (no automatizable sin acceso a tu Supabase):
    1) Ejecutar supabase\migrations\026_audit_complete_fix.sql en el
       SQL Editor de Supabase (es idempotente, se puede reejecutar).
    2) Verificar build local: npm run build
    3) Promocionar manualmente a producción en el dashboard de Vercel
       (plan Hobby no promociona automáticamente).

"@ -ForegroundColor White

# -----------------------------------------------------------------------
# 5. Git (opcional, requiere confirmación explícita)
# -----------------------------------------------------------------------
if ($GitCommit) {
    Write-Step "Git add / commit / push"
    Push-Location $RepoPath
    try {
        git add .
        git status --short
        $confirm = Read-Host "`n¿Confirmas el commit y push de estos cambios? (s/n)"
        if ($confirm -eq "s") {
            git commit -m "fix: completar sistema de auditoria (tipos_obra y 7 tablas mas sin trigger) + capa de log de errores"
            git push
            Write-Ok "Cambios subidos a main."
        } else {
            Write-Warn "Commit cancelado. Los archivos ya están en tu working tree, puedes revisarlos antes de subirlos."
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  (Para hacer commit y push automáticamente, vuelve a ejecutar con -GitCommit)" -ForegroundColor DarkGray
}

# Limpieza de la carpeta temporal
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
