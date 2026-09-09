# bin\summary.ps1 - Tableau de bord final (equivalent Windows de
# bin/summary.sh cote Linux, branche AGENT_HOST : cette machine
# n'heberge jamais Elasticsearch/Kibana/Wazuh Dashboard, seulement des
# agents - donc aucune URL/mot de passe a afficher, uniquement l'etat
# reel des services et les commandes utiles).
#
# AJOUTE LE 2026-09-09 (demande explicite : "je veux qu'a la fin il y
# ait un tableau systemique qui brosse les choses comme sur ELK ...
# pour les postes windows faites pareillement"). Lit UNIQUEMENT l'etat
# REEL de la machine au moment de l'appel (vars.ps1 + Get-Service) -
# jamais une valeur supposee.
#
# Appele automatiquement par orchestrator_windows.ps1 en fin de run
# reussi (ecrit dans state\TABLEAU_DE_BORD_FINAL.txt) - egalement
# appelable a tout moment :
#   & "$env:APP_BIN\summary.ps1"
# (l'operateur d'appel "&" est necessaire ici : sans lui, PowerShell
# tente d'evaluer $env:APP_BIN\... comme une expression et echoue sur
# "\" avec "Jeton inattendu" - erreur reelle rencontree le 2026-09-10).

$BinDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WinRoot = Split-Path -Parent $BinDir
. (Join-Path $WinRoot "vars.ps1")

Write-Host "===================================================================="
Write-Host " $PROJECT_NAME (WINDOWS) - TABLEAU DE BORD"
Write-Host " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "===================================================================="
Write-Host ""
Write-Host "--- AGENT_HOST (Windows) : $AGENT_NAME ---"
Write-Host "Machine ELK_HOST cible : ${FACTORY_HOST_IP}:${LS_BEATS_PORT} (Filebeat/Metricbeat) / :1514-1515 (agent Wazuh)"
Write-Host "Composants actifs      : $($EnabledComponents -join ', ')"
Write-Host ""
Write-Host "--- ETAT DES SERVICES (uniquement les composants actives) ---"
foreach ($comp in $EnabledComponents) {
    switch ($comp) {
        "WAZUH_AGENT" { $svc = "WazuhSvc" }
        "FILEBEAT"    { $svc = "filebeat" }
        "METRICBEAT"  { $svc = "metricbeat" }
        default       { continue }
    }
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq "Running") {
        Write-Host ("{0,-14} actif" -f $svc)
    } elseif ($s) {
        Write-Host ("{0,-14} INACTIF (etat reel : {1} - verifier : Get-Service {2})" -f $svc, $s.Status, $svc)
    } else {
        Write-Host ("{0,-14} ABSENT (service pas encore installe - job pas encore passe sur cette machine)" -f $svc)
    }
}
Write-Host ""
Write-Host "--- SCENARIOS ---"
Write-Host 'Etat des jobs (fait / en attente)  : & "$env:APP_BIN\monitor.ps1"'
Write-Host "Rapport complet du dernier run      : $WinRoot\state\RAPPORT_EXECUTION.txt"
Write-Host 'Relancer la chaine (rejoue le reste): & "$env:APP_HOME\orchestrator_windows.ps1"'
Write-Host "Aucune URL/mot de passe a afficher ici - les tableaux de bord"
Write-Host "(Wazuh Dashboard/Kibana) vivent sur ELK_HOST ($FACTORY_HOST_IP), jamais"
Write-Host "sur ce poste Windows."
Write-Host "===================================================================="
