# WAW_003 - WEF_WAW_BLD_BININST - Installation silencieuse de wazuh-agent (MSI)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$MsiPath = Join-Path $INSTALL_DIR "wazuh-agent.msi"

if (Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue) {
    Write-Host "[WAW_003] wazuh-agent deja installe, installation ignoree."
} else {
    # CORRIGE LE 2026-09-23 (incident reel, premier deploiement machine
    # physique) : la version initiale ne capturait ni le code de sortie
    # reel de msiexec (Start-Process sans -PassThru), ni aucun journal
    # MSI - un echec ne laissait que "service introuvable", sans jamais
    # dire POURQUOI. Corrige : -PassThru pour le vrai code de sortie,
    # /l*v pour un journal MSI complet, les deux affiches en clair en
    # cas d'echec (jamais un echec muet).
    $MsiLogPath = Join-Path $LOG_DIR "wazuh-agent-install.log"
    Write-Host "[WAW_003] Installation silencieuse de wazuh-agent (journal MSI : $MsiLogPath)..."
    $installArgs = "/i `"$MsiPath`" /q /l*v `"$MsiLogPath`" WAZUH_MANAGER=`"$WAZUH_MANAGER_IP`" WAZUH_AGENT_NAME=`"$AGENT_NAME`""
    $proc = Start-Process msiexec.exe -ArgumentList $installArgs -Wait -PassThru
    Write-Host "[WAW_003] msiexec code de sortie : $($proc.ExitCode)"
    if ($proc.ExitCode -ne 0) {
        Write-Host "[WAW_003] ERREUR : msiexec a echoue (code $($proc.ExitCode))."
        if (Test-Path $MsiLogPath) {
            Write-Host "[WAW_003] Dernieres lignes du journal MSI ($MsiLogPath) :"
            Get-Content $MsiLogPath -Tail 25 | ForEach-Object { Write-Host "    $_" }
        }
        exit 1
    }
}

if (-not (Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue)) {
    Write-Host "[WAW_003] ERREUR: service WazuhSvc introuvable apres installation (msiexec a pourtant rendu le code 0 - voir le journal MSI ci-dessus)."
    exit 1
}

Write-Host "[WAW_003] OK."
exit 0
