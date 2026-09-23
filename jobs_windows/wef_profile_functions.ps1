# jobs_windows\wef_profile_functions.ps1
#
# AJOUTE LE 2026-09-23 (demande explicite : "commandes simples et
# courtes" - retrouver, cote Windows, le meme reflexe court que
# $APP_BIN/order.sh cote Linux).
#
# SOURCE DE VERITE UNIQUE - ce fichier vit dans le depot (git), 100%
# identique sur toute machine (jamais de chemin en dur : chaque fonction
# lit $env:APP_HOME/$env:APP_BIN AU MOMENT DE L'APPEL, jamais fige a
# l'ecriture - contrairement a un profil genere avec le chemin en dur,
# celui-ci reste valide meme si le depot est deplace/re-clone, tant que
# env.ps1 a ete relance une fois). NE PAS EDITER UN PROFIL POWERSHELL A
# LA MAIN avec ce contenu - toujours modifier CE fichier ici, puis
# relancer env.ps1 (idempotent, voir son en-tete).
#
# Installe automatiquement (bloc marque, idempotent) dans le vrai profil
# PowerShell de l'operateur par env.ps1 - JAMAIS le profil entier
# ecrase (contrairement a /etc/profile.d cote Linux qui est un fichier
# dedie : $PROFILE Windows est personnel, peut deja contenir d'autres
# personnalisations de l'operateur que ce projet ne doit jamais toucher).
#
# Usage, depuis N'IMPORTE QUEL repertoire, une fois installe (nouvelle
# session PowerShell apres le premier "env.ps1") :
#   wef            -> lance la chaine complete de jobs (orchestrator_windows.ps1)
#   wef-monitor    -> etat des jobs (fait / en attente)
#   wef-summary    -> tableau de bord final (etat reel des services)

function wef {
    & "$env:APP_HOME\orchestrator_windows.ps1"
}

function wef-monitor {
    & "$env:APP_BIN\monitor.ps1"
}

function wef-summary {
    & "$env:APP_BIN\summary.ps1"
}
