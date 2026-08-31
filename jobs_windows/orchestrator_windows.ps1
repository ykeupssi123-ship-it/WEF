# =====================================================================
#  WAZ_ELK_FACTORY - ORCHESTRATEUR WINDOWS (agent)
#  A executer en PowerShell "Administrateur"
#  Lit jobs_table_windows.csv, resout les dependances et execute les
#  jobs. Aucune donnee en dur : tout vient de vars.ps1
#
#  ARRET AU PREMIER ECHEC (fail-fast), meme logique que
#  orchestrator.sh (Linux) : les jobs suivants dependent de la
#  reussite du precedent. A la fin (succes OU echec), un rapport est
#  toujours ecrit dans state\RAPPORT_EXECUTION.txt.
#
#  FILTRAGE PAR COMPOSANT : chaque ligne de jobs_table_windows.csv a
#  une colonne COMPONENT (WAZUH_AGENT / FILEBEAT / METRICBEAT). Seuls
#  les jobs dont le COMPONENT figure dans $EnabledComponents (vars.ps1)
#  sont joues - equivalent Windows du filtrage par ROLE cote Linux.
# =====================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

New-Item -ItemType Directory -Force -Path $STATE_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$RunLog = Join-Path $LOG_DIR "orchestrator_windows_$ts.log"
$JobsCsv = Join-Path $ScriptDir "jobs_table_windows.csv"
$ReportFile = Join-Path $STATE_DIR "RAPPORT_EXECUTION.txt"

$Script:FailedJobId = $null
$Script:FailedJobName = $null

function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    Add-Content -Path $RunLog -Value $line
}

function Job-Done($outCond) {
    Test-Path (Join-Path $STATE_DIR "$outCond.ok")
}

function Mark-Done($outCond) {
    Get-Date -Format "o" | Set-Content (Join-Path $STATE_DIR "$outCond.ok")
}

function Write-Report {
    $jobs = Import-Csv -Path $JobsCsv
    $lines = @()
    $lines += "=================================================="
    $lines += " RAPPORT D'EXECUTION - $PROJECT_NAME (WINDOWS)"
    $lines += "=================================================="
    $lines += "Date        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "Machine     : $env:COMPUTERNAME"
    $lines += "Agent       : $AGENT_NAME"
    $lines += "Log complet : $RunLog"
    $lines += ""
    if ($Script:FailedJobId) {
        $lines += "RESULTAT : ARRET SUR ECHEC"
        $lines += "Job en echec : $($Script:FailedJobId) ($($Script:FailedJobName))"
    } else {
        $lines += "RESULTAT : TERMINE SANS ECHEC"
    }
    $lines += ""
    $lines += "--- JOBS TERMINES AVEC SUCCES ---"
    $okFiles = Get-ChildItem $STATE_DIR -Filter "*.ok" -ErrorAction SilentlyContinue
    if ($okFiles) {
        $okFiles | ForEach-Object { $lines += $_.BaseName }
    } else {
        $lines += "(aucun)"
    }
    $lines += ""
    $lines += ""
    $lines += "--- COMPOSANTS ACTIFS SUR CETTE MACHINE ---"
    $lines += ($EnabledComponents -join ", ")
    $lines += ""
    $lines += "--- JOBS JAMAIS ATTEINTS (composants actifs uniquement) ---"
    $notReached = 0
    foreach ($job in $jobs) {
        if ($EnabledComponents -notcontains $job.COMPONENT) { continue }
        if (Job-Done $job.OUT_CONDITION) { continue }
        $lines += "$($job.JOB_ID) ($($job.JOB_NAME))"
        $notReached = 1
    }
    if ($notReached -eq 0) { $lines += "(aucun - tout ce qui concerne les composants actifs est termine)" }
    $lines += "=================================================="

    $lines | Set-Content -Path $ReportFile
    Write-Log "Rapport ecrit dans $ReportFile"
}

Write-Log "=== Demarrage orchestrateur WAZ_ELK_FACTORY (Windows) - AGENT=$AGENT_NAME ==="

# Pas de "exit" a l'interieur du try/catch ci-dessous : le comportement
# de "exit" vis-a-vis d'un bloc "finally" englobant varie selon l'hote
# PowerShell (console vs ISE vs pwsh) - on utilise donc un drapeau et un
# SEUL point de sortie, tout en bas, hors de tout bloc try, pour
# garantir que le rapport est ecrit dans TOUS les cas sans ambiguite.
$Script:StopNow = $false
$Script:ExitCode = 0

try {
    $jobs = Import-Csv -Path $JobsCsv

    for ($pass = 1; $pass -le 10; $pass++) {
        $progressed = $false
        foreach ($job in $jobs) {
            if ($Script:StopNow) { break }
            if ($EnabledComponents -notcontains $job.COMPONENT) { continue }
            if (Job-Done $job.OUT_CONDITION) { continue }

            $ready = $true
            if ($job.IN_CONDITIONS -ne "NONE") {
                foreach ($dep in $job.IN_CONDITIONS -split '\|') {
                    if (-not (Job-Done $dep)) { $ready = $false }
                }
            }
            if (-not $ready) { continue }

            Write-Log "--- $($job.JOB_ID) ($($job.JOB_NAME)) : $($job.DESCRIPTION) ---"
            $scriptPath = Join-Path $ScriptDir $job.SCRIPT_FILE
            try {
                & $scriptPath *>> $RunLog
                if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "Exit code $LASTEXITCODE" }
                Mark-Done $job.OUT_CONDITION
                Write-Log "$($job.JOB_ID) -> OK ($($job.OUT_CONDITION))"
                $progressed = $true
            } catch {
                Write-Log "$($job.JOB_ID) -> ECHEC : $_"
                Write-Log "Arret orchestrateur."
                $Script:FailedJobId = $job.JOB_ID
                $Script:FailedJobName = $job.JOB_NAME
                $Script:ExitCode = 1
                $Script:StopNow = $true
            }
        }
        if ($Script:StopNow) { break }
        if (-not $progressed) { break }
    }

    if (-not $Script:StopNow) {
        Write-Log "=== Fin orchestrateur ==="
        Write-Log "Etat final (jobs termines) :"
        Get-ChildItem $STATE_DIR -Filter "*.ok" | ForEach-Object { Write-Log $_.Name }
    }
} finally {
    Write-Report
}

exit $Script:ExitCode
