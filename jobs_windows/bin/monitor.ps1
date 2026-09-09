# bin\monitor.ps1 - Etat des jobs (equivalent Windows partiel de
# bin/monitor.sh cote Linux).
#
# AJOUTE LE 2026-09-09 (demande explicite : "je veux appeler les
# commandes avec les variables ... pour les postes windows faites
# pareillement"). LIMITE HONNETE, assumee : orchestrator_windows.ps1
# ne pose aujourd'hui que des marqueurs *.ok (job termine) - il n'ecrit
# aucun marqueur "en cours" (*.running), aucun etat "gele" (HELD) et
# aucun historique dure (JOBS_HISTORY.csv). Ce script montre donc
# fait/en attente uniquement - jamais "en cours" ou "gele", features
# qui n'existent pas (encore) dans ce kit et ne sont pas simulees ici.
#
# Usage : $env:APP_BIN\monitor.ps1

$BinDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WinRoot = Split-Path -Parent $BinDir
. (Join-Path $WinRoot "vars.ps1")
$JobsCsv = Join-Path $WinRoot "jobs_table_windows.csv"

function Job-Done($outCond) {
    Test-Path (Join-Path $STATE_DIR "$outCond.ok")
}

Write-Host "===================================================================="
Write-Host " ETAT DES JOBS (WINDOWS) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "===================================================================="
Write-Host "Composants actifs sur cette machine : $($EnabledComponents -join ', ')"
Write-Host ""

$jobs = Import-Csv -Path $JobsCsv

Write-Host "--- TERMINES ---"
$doneCount = 0
foreach ($job in $jobs) {
    if ($EnabledComponents -notcontains $job.COMPONENT) { continue }
    if (Job-Done $job.OUT_CONDITION) {
        Write-Host "$($job.JOB_ID) ($($job.JOB_NAME))"
        $doneCount++
    }
}
if ($doneCount -eq 0) { Write-Host "(aucun)" }

Write-Host ""
Write-Host "--- EN ATTENTE (dependance non satisfaite) ---"
$waitCount = 0
foreach ($job in $jobs) {
    if ($EnabledComponents -notcontains $job.COMPONENT) { continue }
    if (Job-Done $job.OUT_CONDITION) { continue }

    $missing = @()
    if ($job.IN_CONDITIONS -ne "NONE") {
        foreach ($dep in $job.IN_CONDITIONS -split '\|') {
            if (-not (Job-Done $dep)) { $missing += $dep }
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "$($job.JOB_ID) ($($job.JOB_NAME)) : EN ATTENTE de -> $($missing -join ', ')"
        $waitCount++
    }
}
if ($waitCount -eq 0) { Write-Host "(aucun job bloque sur une dependance non satisfaite)" }
Write-Host "===================================================================="
