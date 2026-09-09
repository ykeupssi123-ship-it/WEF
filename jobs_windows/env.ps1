# env.ps1 - Equivalent Windows de setup/env.sh (cote Linux) : rend
# possible d'appeler n'importe quel script du kit Windows depuis
# n'importe quel repertoire, via 2 variables d'environnement
# persistantes ($env:APP_HOME/$env:APP_BIN, actives dans toute NOUVELLE
# session apres ce script - meme gotcha que /etc/profile.d cote Linux).
#
# AJOUTE LE 2026-09-09 (demande explicite : "je veux que de la meme
# maniere l'exploitation ... soit pareil ... je veux appeler les
# commandes avec les variables ... pour les postes windows faites
# pareillement"). Memes 2 roles que cote Linux ($APP_HOME/$APP_BIN),
# MEMES NOMS (aucune collision possible : jamais la meme machine que le
# Linux ELK_HOST/AGENT_HOST) - pour que l'operateur garde exactement le
# meme reflexe mental des deux cotes.
#
# PAS d'equivalent $APP_INF ici : cote Linux, setup/ separe
# "installation ponctuelle de service" de "jobs metier" - cote Windows,
# il n'existe aucun service/tache planifiee a installer separement
# (l'installation EST la chaine de jobs elle-meme, jouee une fois par
# machine). Rien a regrouper qui n'existe pas deja.
#
# CORRIGE LE 2026-09-09 (incident reel, premiere execution sur une VM
# agent Windows non-admin) : la version initiale ecrivait en portee
# "Machine" (HKLM) sans jamais verifier le resultat - `SetEnvironmentVariable`
# echoue silencieusement (exception non interceptee, script poursuit
# quand meme) si la session n'est pas Administrateur, et le script
# annoncait "Variables ecrites" meme apres cet echec reel. Corrige a la
# racine : plus besoin d'etre Administrateur du tout - ces 2 variables
# ne sont qu'un confort operateur (aucun service ne les lit), la portee
# "User" (HKCU, jamais de droits speciaux requis) suffit et persiste
# tout autant pour les commandes de cet operateur. Chaque ecriture est
# desormais verifiee reellement (relecture immediate) avant d'annoncer
# un succes.
#
# A LANCER UNE FOIS PAR MACHINE (PowerShell normal, admin non requis) :
#   .\env.ps1
# Puis ouvrez une NOUVELLE session PowerShell - $env:APP_HOME/$env:APP_BIN
# ne sont pas retroactifs dans la session qui vient de lancer ce script.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $ScriptDir "bin"

function Set-PersistentVar($name, $value) {
    try {
        [Environment]::SetEnvironmentVariable($name, $value, "User")
    } catch {
        Write-Host "[env.ps1] ERREUR : impossible d'ecrire $name (User) : $_" -ForegroundColor Red
        return $false
    }
    # Verification reelle - jamais un succes annonce sans relecture.
    $reread = [Environment]::GetEnvironmentVariable($name, "User")
    if ($reread -ne $value) {
        Write-Host "[env.ps1] ERREUR : $name relu different de la valeur ecrite (attendu '$value', lu '$reread')." -ForegroundColor Red
        return $false
    }
    return $true
}

$okHome = Set-PersistentVar "APP_HOME" $ScriptDir
$okBin  = Set-PersistentVar "APP_BIN"  $BinDir

if ($okHome -and $okBin) {
    Write-Host "APP_HOME = $ScriptDir"
    Write-Host "APP_BIN  = $BinDir"
    Write-Host ""
    Write-Host "Variables ecrites et verifiees (portee utilisateur courant). Ouvrez une"
    Write-Host "NOUVELLE session PowerShell pour qu'elles soient actives (`$env:APP_HOME, `$env:APP_BIN)."
} else {
    Write-Host ""
    Write-Host "[env.ps1] ECHEC : au moins une variable n'a pas ete ecrite - voir l'erreur ci-dessus." -ForegroundColor Red
    exit 1
}
