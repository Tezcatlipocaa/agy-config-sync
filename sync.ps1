<#
.SYNOPSIS
    agy-config-sync: Multi-machine synchronization and AI curation engine for Antigravity CLI.
.DESCRIPTION
    Cross-platform synchronization tool supporting Windows, macOS, and Linux.
    Commands:
      status                    Show current machine status and staging state
      add-machine <profile>     Register current machine under a profile name
      snapshot [-Profile <p>]   Capture machine state and auto-discover plugins/MCPs
      stage [-Profile <p>]      Assemble staging/ directory for target machine
      apply [-DryRun]           Safely apply configuration to ~/.gemini (requires agy closed)
#>
[CmdletBinding()]
param (
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('status', 'add-machine', 'snapshot', 'stage', 'apply')]
    [string]$Action,

    [Parameter(Position = 1)]
    [string]$Profile,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Ensure git pre-commit hook is active
try { git config core.hooksPath hooks 2>$null } catch {}

# Directory paths
$RepoRoot = $PSScriptRoot
$GeminiHome = Join-Path $HOME ".gemini"
$GeminiConfig = Join-Path $GeminiHome "config"
$GeminiCli = Join-Path $GeminiHome "antigravity-cli"
$ManifestPath = Join-Path $RepoRoot "manifest.json"
$HostMapPath = Join-Path $RepoRoot "host-map.json"
$EnvLocalPath = Join-Path $RepoRoot ".env.local"
$StagingPath = Join-Path $RepoRoot "staging"
$CachePath = Join-Path $RepoRoot ".cache"
$HostName = [System.Net.Dns]::GetHostName()

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Test-AgyRunning {
    $processes = Get-Process -Name "agy","antigravity","gemini" -ErrorAction SilentlyContinue
    return ($null -ne $processes -and $processes.Count -gt 0)
}

function Get-HostMap {
    if (Test-Path $HostMapPath) {
        try { return Get-Content $HostMapPath -Raw | ConvertFrom-Json } catch { return [PSCustomObject]@{} }
    }
    return [PSCustomObject]@{}
}

function Save-HostMap($mapObj) {
    $mapObj | ConvertTo-Json -Depth 4 | Set-Content $HostMapPath -Encoding utf8
}

# Resolve active profile
$HostMap = Get-HostMap
if (-not $Profile) {
    if ($HostMap.PSObject.Properties[$HostName]) {
        $Profile = $HostMap.$HostName
    }
}

# -----------------------------------------------------------------------------
# COMMAND: STATUS
# -----------------------------------------------------------------------------
if ($Action -eq 'status') {
    Write-Host "==========================================================" -ForegroundColor Magenta
    Write-Host " agy-config-sync - Machine Status" -ForegroundColor Magenta
    Write-Host "==========================================================" -ForegroundColor Magenta
    Write-Info "Current Hostname:  $HostName"
    Write-Info "Resolved Profile:  $($Profile ? $Profile : '<Unregistered Machine>')"
    Write-Info "Antigravity Path:  $GeminiHome"
    
    $registeredCount = ($HostMap.PSObject.Properties | Measure-Object).Count
    Write-Info "Registered Hosts:  $registeredCount machine(s)"
    foreach ($prop in $HostMap.PSObject.Properties) {
        Write-Host "  - $($prop.Name) -> $($prop.Value)" -ForegroundColor Gray
    }

    if (Test-Path $EnvLocalPath) {
        Write-Success ".env.local detected"
    } else {
        Write-Warn ".env.local not found (copy .env.example to set local secrets)"
    }

    if (Test-AgyRunning) {
        Write-Warn "Antigravity CLI (agy) is currently running"
    } else {
        Write-Success "Antigravity CLI (agy) is closed (safe to apply)"
    }

    if (Test-Path $StagingPath) {
        if (Test-Path (Join-Path $StagingPath "PENDIENTE-AGENTE.json")) {
            Write-Warn "staging/ has pending tasks requiring Agent resolution"
        } else {
            Write-Success "staging/ is ready to be applied"
        }
    } else {
        Write-Info "staging/ not initialized. Run: .\sync.ps1 stage"
    }
    exit 0
}

# -----------------------------------------------------------------------------
# COMMAND: ADD-MACHINE
# -----------------------------------------------------------------------------
if ($Action -eq 'add-machine') {
    if (-not $Profile) {
        Write-Err "Usage: .\sync.ps1 add-machine <profile-name>"
        exit 1
    }

    $HostMap | Add-Member -NotePropertyName $HostName -NotePropertyValue $Profile -Force
    Save-HostMap $HostMap
    Write-Success "Registered machine '$HostName' as profile '$Profile' in host-map.json"

    # Create overrides/<profile>.json if not exists
    $overrideFile = Join-Path $RepoRoot "overrides\$Profile.json"
    if (-not (Test-Path $overrideFile)) {
        $overrideObj = [PSCustomObject]@{
            profile = $Profile
            hostname = $HostName
            description = "Machine-specific overrides for $Profile"
            disabledPlugins = @()
            extraMcpServers = [PSCustomObject]@{}
        }
        $overrideObj | ConvertTo-Json -Depth 4 | Set-Content $overrideFile -Encoding utf8
        Write-Success "Created overrides template: overrides\$Profile.json"
    }
    exit 0
}

# Ensure profile is defined for snapshot/stage/apply
if (-not $Profile) {
    Write-Err "Machine '$HostName' is not registered. Run first: .\sync.ps1 add-machine <profile-name>"
    exit 1
}

# -----------------------------------------------------------------------------
# COMMAND: SNAPSHOT (With Auto-Discovery)
# -----------------------------------------------------------------------------
if ($Action -eq 'snapshot') {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Capturing snapshot for profile: $Profile ($HostName)" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    # Auto-register if not yet in host-map
    if (-not $HostMap.PSObject.Properties[$HostName]) {
        $HostMap | Add-Member -NotePropertyName $HostName -NotePropertyValue $Profile -Force
        Save-HostMap $HostMap
        Write-Success "Auto-registered '$HostName' as '$Profile'"
    }

    $SnapshotDir = Join-Path $RepoRoot "snapshots\$Profile"
    New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null

    # Metadata
    $meta = [PSCustomObject]@{
        profile = $Profile
        hostname = $HostName
        capturedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        os = [System.Environment]::OSVersion.VersionString
        user = $env:USERNAME
    }
    $meta | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $SnapshotDir "metadata.json") -Encoding utf8

    # Capture GEMINI.md
    $geminiMd = Join-Path $GeminiHome "GEMINI.md"
    if (Test-Path $geminiMd) {
        Copy-Item $geminiMd (Join-Path $SnapshotDir "GEMINI.md") -Force
        $copyGemini = Join-Path $RepoRoot "copy\GEMINI.md"
        New-Item -ItemType Directory -Path (Split-Path $copyGemini) -Force | Out-Null
        Copy-Item $geminiMd $copyGemini -Force
    }

    # Capture config.json
    $cfgJson = Join-Path $GeminiConfig "config.json"
    if (Test-Path $cfgJson) {
        Copy-Item $cfgJson (Join-Path $SnapshotDir "config.json") -Force
        $copyCfg = Join-Path $RepoRoot "copy\config\config.json"
        New-Item -ItemType Directory -Path (Split-Path $copyCfg) -Force | Out-Null
        Copy-Item $cfgJson $copyCfg -Force
    }

    # Capture plugins list (sanitizing personal home path)
    try {
        $pluginList = agy plugin list --json 2>$null
        if ($pluginList) {
            $pluginListSanitized = $pluginList -replace [regex]::Escape($GeminiHome), '{{GEMINI_HOME}}'
            $pluginListSanitized | Set-Content (Join-Path $SnapshotDir "plugins-installed.json") -Encoding utf8
        }
    } catch {}

    # AUTO-DISCOVERY of plugins in ~/.gemini/config/plugins
    $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    $manifestMap = @{}
    foreach ($mItem in $manifest.items) { $manifestMap[$mItem.id] = $mItem }

    $pluginsDir = Join-Path $GeminiConfig "plugins"
    if (Test-Path $pluginsDir) {
        $installedDirs = Get-ChildItem -Path $pluginsDir -Directory
        foreach ($pDir in $installedDirs) {
            $pName = $pDir.Name
            $itemId = "plugin:$pName"
            $hasGit = Test-Path (Join-Path $pDir.FullName ".git")

            if ($hasGit) {
                # Level B: Git upstream
                $remoteUrl = git -C $pDir.FullName remote get-url origin 2>$null
                $sha = git -C $pDir.FullName rev-parse --short HEAD 2>$null
                if ($remoteUrl -and $sha) {
                    Write-Info "Auto-discovered Git plugin (Level B): $pName"
                    $overlayDir = "overlays/$pName"
                    $manifestMap[$itemId] = [PSCustomObject]@{
                        id = $itemId
                        level = "B"
                        upstream = $remoteUrl.Trim()
                        sha = $sha.Trim()
                        overlay = $overlayDir
                        target = "{{GEMINI_CONFIG}}/plugins/$pName"
                    }

                    # Extract local overlay changes
                    $fullOverlay = Join-Path $RepoRoot $overlayDir
                    New-Item -ItemType Directory -Path $fullOverlay -Force | Out-Null
                    $dirty = git -C $pDir.FullName status --porcelain 2>$null
                    if ($dirty) {
                        foreach ($line in $dirty) {
                            $relPath = ($line.Substring(3)).Trim()
                            # Skip machine-specific hooks from overlay
                            if ($relPath -match "hooks\.json$") { continue }
                            $srcF = Join-Path $pDir.FullName $relPath
                            $dstF = Join-Path $fullOverlay $relPath
                            if (Test-Path $srcF -PathType Leaf) {
                                New-Item -ItemType Directory -Path (Split-Path $dstF) -Force | Out-Null
                                Copy-Item $srcF $dstF -Force
                            }
                        }
                    }
                }
            } else {
                # Level A: Lightweight copy
                Write-Info "Auto-discovered standalone plugin (Level A): $pName"
                $copyRel = "copy/plugins/$pName"
                $manifestMap[$itemId] = [PSCustomObject]@{
                    id = $itemId
                    level = "A"
                    source = $copyRel
                    target = "{{GEMINI_CONFIG}}/plugins/$pName"
                }

                $fullCopy = Join-Path $RepoRoot $copyRel
                if (Test-Path $fullCopy) { Remove-Item $fullCopy -Recurse -Force }
                New-Item -ItemType Directory -Path $fullCopy -Force | Out-Null
                Get-ChildItem -Path $pDir.FullName -Exclude ".git","__pycache__","node_modules" | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $fullCopy -Recurse -Force
                }
            }
        }
    }

    # Save updated manifest
    $manifest.items = @($manifestMap.Values)
    $manifest | ConvertTo-Json -Depth 6 | Set-Content $ManifestPath -Encoding utf8

    Write-Success "Snapshot completed for '$Profile' in snapshots\$Profile"
    exit 0
}

# -----------------------------------------------------------------------------
# COMMAND: STAGE
# -----------------------------------------------------------------------------
if ($Action -eq 'stage') {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Assembling staging/ for profile: $Profile" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    if (Test-Path $StagingPath) { Remove-Item $StagingPath -Recurse -Force }
    New-Item -ItemType Directory -Path $StagingPath -Force | Out-Null

    $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    $pendientes = @()

    # Load .env.local
    $envVars = @{}
    if (Test-Path $EnvLocalPath) {
        Get-Content $EnvLocalPath | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
                $parts = $line.Split("=", 2)
                $envVars[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }

    foreach ($item in $manifest.items) {
        $resolvedTarget = $item.target `
            -replace '\{\{GEMINI_HOME\}\}', $GeminiHome `
            -replace '\{\{GEMINI_CONFIG\}\}', $GeminiConfig `
            -replace '\{\{GEMINI_CLI\}\}', $GeminiCli

        $stagingRelative = $resolvedTarget.Replace($GeminiHome, "").TrimStart("\/")
        $stagingTarget = Join-Path $StagingPath $stagingRelative

        # Level A
        if ($item.level -eq 'A') {
            $src = Join-Path $RepoRoot $item.source
            if (Test-Path $src) {
                New-Item -ItemType Directory -Path (Split-Path $stagingTarget) -Force | Out-Null
                if (Test-Path $src -PathType Container) {
                    Copy-Item $src $stagingTarget -Recurse -Force
                } else {
                    Copy-Item $src $stagingTarget -Force
                }
            }
        }

        # Level B
        elseif ($item.level -eq 'B') {
            $safeId = $item.id -replace ':', '_'
            $cacheUpstream = Join-Path $CachePath "upstreams\$safeId"
            if (-not (Test-Path (Join-Path $cacheUpstream ".git"))) {
                Write-Info "Cloning upstream: $($item.id)..."
                New-Item -ItemType Directory -Path $cacheUpstream -Force | Out-Null
                git clone --quiet $item.upstream $cacheUpstream
            }
            git -C $cacheUpstream checkout --quiet $item.sha 2>$null

            New-Item -ItemType Directory -Path $stagingTarget -Force | Out-Null
            Get-ChildItem -Path $cacheUpstream -Exclude ".git","__pycache__","node_modules" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $stagingTarget -Recurse -Force
            }

            $overlayPath = Join-Path $RepoRoot $item.overlay
            if (Test-Path $overlayPath) {
                Get-ChildItem -Path $overlayPath -Recurse | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
                    $rel = $_.FullName.Replace($overlayPath, "").TrimStart("\/")
                    $dest = Join-Path $stagingTarget $rel
                    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
                    Copy-Item $_.FullName $dest -Force
                }
            }
        }

        # Level C
        elseif ($item.level -eq 'C') {
            $tmplPath = Join-Path $RepoRoot $item.template
            if (Test-Path $tmplPath) {
                $content = Get-Content $tmplPath -Raw
                $content = $content -replace '\{\{GEMINI_CONFIG\}\}', ($GeminiConfig -replace '\\', '\\')
                $content = $content -replace '\{\{GEMINI_HOME\}\}', ($GeminiHome -replace '\\', '\\')

                if ($item.id -eq 'file:settings-json') {
                    $currentSettings = $null
                    $settingsPath = Join-Path $GeminiCli "settings.json"
                    if (Test-Path $settingsPath) {
                        try { $currentSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch {}
                    }
                    $modelVal = if ($currentSettings -and $currentSettings.model) { $currentSettings.model } else { "Gemini 4 Argon (Medium)" }
                    $permVal = if ($currentSettings -and $currentSettings.toolPermission) { $currentSettings.toolPermission } else { "always-proceed" }
                    $twArr = if ($currentSettings -and $currentSettings.trustedWorkspaces) { $currentSettings.trustedWorkspaces } else { @() }
                    $twJson = ($twArr | ForEach-Object { "    ""$($_ -replace '\\', '\\')""" }) -join ",`n"
                    $content = "{`n  ""model"": ""$modelVal"",`n  ""toolPermission"": ""$permVal"",`n  ""trustedWorkspaces"": [`n$twJson`n  ]`n}"
                }

                New-Item -ItemType Directory -Path (Split-Path $stagingTarget) -Force | Out-Null
                $content | Set-Content $stagingTarget -Encoding utf8
            }
        }
    }

    if ($pendientes.Count -gt 0) {
        $pendientes | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $StagingPath "PENDIENTE-AGENTE.json") -Encoding utf8
        Write-Warn "staging/PENDIENTE-AGENTE.json generated with $($pendientes.Count) pending task(s)."
    } else {
        Write-Success "Staging successfully prepared without pending items."
    }
    exit 0
}

# -----------------------------------------------------------------------------
# COMMAND: APPLY
# -----------------------------------------------------------------------------
if ($Action -eq 'apply') {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Applying configuration to: $GeminiHome" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    if (-not $DryRun -and (Test-AgyRunning)) {
        Write-Err "Antigravity CLI (agy) is currently open. Close it before applying."
        exit 1
    }
    if ($DryRun -and (Test-AgyRunning)) {
        Write-Warn "Antigravity CLI (agy) is currently open. You must close it for a real apply."
    }

    if (-not (Test-Path $StagingPath)) {
        Write-Err "staging/ directory not found. Run first: .\sync.ps1 stage"
        exit 1
    }

    if (Test-Path (Join-Path $StagingPath "PENDIENTE-AGENTE.json")) {
        Write-Err "Pending tasks exist in staging/PENDIENTE-AGENTE.json. Resolve them before applying."
        exit 1
    }

    if ($DryRun) {
        Write-Warn "[DRY-RUN] Files that would be applied to $GeminiHome:"
        Get-ChildItem -Path $StagingPath -Recurse | ForEach-Object {
            $rel = $_.FullName.Replace($StagingPath, "").TrimStart("\/")
            $dest = Join-Path $GeminiHome $rel
            Write-Host " -> $rel (Exists: $(Test-Path $dest))" -ForegroundColor Gray
        }
        Write-Success "[DRY-RUN] Verification complete. Run without -DryRun to apply."
        exit 0
    }

    # Backup rotation (keep last 5)
    $BackupDir = Join-Path $RepoRoot "backups\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Info "Creating safety backup in: $BackupDir"
    foreach ($file in @("GEMINI.md", "config\config.json", "config\mcp_config.json", "antigravity-cli\settings.json")) {
        $src = Join-Path $GeminiHome $file
        if (Test-Path $src) {
            $dst = Join-Path $BackupDir $file
            New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
            Copy-Item $src $dst -Force
        }
    }

    # Copy files
    Write-Info "Copying prepared staging files to ~/.gemini..."
    Get-ChildItem -Path $StagingPath -Recurse | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
        $rel = $_.FullName.Replace($StagingPath, "").TrimStart("\/")
        $dest = Join-Path $GeminiHome $rel
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        Copy-Item $_.FullName $dest -Force
    }

    Write-Success "=========================================================="
    Write-Success " Configuration applied successfully in $GeminiHome"
    Write-Success "=========================================================="
    exit 0
}
