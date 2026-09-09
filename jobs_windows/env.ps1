# env.ps1 - Equivalent Windows de setup/env.sh (cote Linux) : rend
# possible d'appeler n'importe quel script du kit Windows depuis
# n'importe quel repertoire, via 2 variables d'environnement
# persistantes (PORTEE MACHINE - visibles de toute session, tout
# utilisateur, apres une NOUVELLE session).
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
# A LANCER UNE FOIS PAR MACHINE, en PowerShell "Administrateur" (portee
# Machine = necessite les droits admin) :
#   .\env.ps1
# Puis ouvrez une NOUVELLE session PowerShell (meme gotcha que cote
# Linux avec /etc/profile.d) - $env:APP_HOME/$env:APP_BIN ne sont pas
# retroactifs dans la session qui vient de lancer ce script.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BinDir = Join-Path $ScriptDir "bin"

[Environment]::SetEnvironmentVariable("APP_HOME", $ScriptDir, "Machine")
[Environment]::SetEnvironmentVariable("APP_BIN", $BinDir, "Machine")

Write-Host "APP_HOME = $ScriptDir"
Write-Host "APP_BIN  = $BinDir"
Write-Host ""
Write-Host "Variables ecrites (portee Machine). Ouvrez une NOUVELLE session"
Write-Host "PowerShell pour qu'elles soient actives (`$env:APP_HOME, `$env:APP_BIN)."
