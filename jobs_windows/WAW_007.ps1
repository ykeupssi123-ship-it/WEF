# WAW_007 - WEF_WAW_RUN_VTWATCHDIR - Surveillance FIM temps reel (VirusTotal)
#
# AJOUTE LE 2026-09-23 (demande explicite : "il faut les jobs aussi pour
# ca concernant virustotal ... et tout ce qui est de la collecte"),
# equivalent Windows exact de jobs/WAG_009_VT_WATCH_DIR.sh (cote Linux) :
# ouvre les zones ou un fichier peut legitimement apparaitre sur CETTE
# machine, deja surveillees par l'integration VirusTotal centrale
# (WAZ_050, tourne sur VM1/ELK_HOST - filtre par rule_id, jamais par
# agent, donc AUCUNE configuration cote manager necessaire ici, meme
# principe deja verifie ce soir avec VM2).
#
# DEUX PIEGES REELS EVITES DES LA CONCEPTION (jamais decouverts a
# l'usage, verifies en lisant le vrai ossec.conf de CETTE machine
# AVANT d'ecrire ce job) :
#   1. WazuhSvc tourne en tant que SYSTEM, pas l'utilisateur interactif -
#      %USERPROFILE% resolu PAR LE SERVICE pointerait vers le profil
#      systeme, jamais C:\Users\<vous>. Corrige : les chemins reels sont
#      resolus ICI (au moment ou CE script tourne, en session
#      interactive) et ecrits en DUR dans ossec.conf - jamais une
#      variable d'environnement laissee pour le service.
#   2. Le ossec.conf par defaut de cet agent exclut deja ".log$|.htm$|
#      .jpg$|.png$|.chm$|.pnf$|.evtx$" (meme piege que ".log$" trouve ce
#      soir cote Linux, ici deja present nativement) - a garder en tete
#      pour tout futur test manuel (jamais deposer un fichier .log).
#
# Liste construite DYNAMIQUEMENT (jamais devinee) : Downloads/Desktop/
# Documents de chaque VRAI profil utilisateur present sous C:\Users
# (detecte par la presence de NTUSER.DAT - exclut Public/Default/All
# Users, qui ne sont jamais de vrais profils connectables).
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "vars.ps1")

$OssecConf = "C:\Program Files (x86)\ossec-agent\ossec.conf"
if (-not (Test-Path $OssecConf)) {
    Write-Host "[WAW_007] ERREUR: $OssecConf introuvable (WAW_003 doit avoir tourne)."
    exit 1
}

Write-Host "[WAW_007] Decouverte des profils utilisateurs reels sous C:\Users..."
$WatchDirs = New-Object System.Collections.Generic.List[string]
Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notin @("Public", "Default", "Default User", "All Users") -and
    (Test-Path (Join-Path $_.FullName "NTUSER.DAT"))
} | ForEach-Object {
    foreach ($sub in @("Downloads", "Desktop", "Documents")) {
        $p = Join-Path $_.FullName $sub
        if (Test-Path $p) { $WatchDirs.Add($p) }
    }
}

if ($WatchDirs.Count -eq 0) {
    Write-Host "[WAW_007] ERREUR: aucun dossier reel decouvert sous C:\Users - rien a surveiller."
    exit 1
}
Write-Host "[WAW_007] Dossiers reellement decouverts sur cette machine :"
$WatchDirs | ForEach-Object { Write-Host "    $_" }

$Marker = "<!-- WEF_VT_WATCH_CONFIG (WAW_007, genere automatiquement - ne pas editer a la main) -->"
$MarkerEnd = "<!-- WEF_VT_WATCH_CONFIG_END -->"

$content = Get-Content $OssecConf -Raw
if ($content -match [regex]::Escape($Marker)) {
    Write-Host "[WAW_007] Bloc deja pose, retrait avant reecriture (evite les doublons a chaque rejeu)..."
    $removePattern = "(?s)" + [regex]::Escape($Marker) + ".*?" + [regex]::Escape($MarkerEnd) + "\r?\n?"
    $content = [regex]::Replace($content, $removePattern, "")
}

$dirLines = ($WatchDirs | ForEach-Object {
    "    <directories realtime=`"yes`" report_changes=`"yes`">$_</directories>"
}) -join "`r`n"

$block = "$Marker`r`n$dirLines`r`n$MarkerEnd`r`n  </syscheck>"
$newContent = [regex]::Replace($content, "(?m)^\s*</syscheck>\s*$", { param($m) $block }, 1)

if ($newContent -eq $content) {
    Write-Host "[WAW_007] ERREUR: balise </syscheck> introuvable dans $OssecConf - structure inattendue."
    exit 1
}

Set-Content -Path $OssecConf -Value $newContent -NoNewline

$verify = Get-Content $OssecConf -Raw
if ($verify -notmatch [regex]::Escape($Marker)) {
    Write-Host "[WAW_007] ERREUR: bloc absent apres ecriture."
    exit 1
}

Write-Host "[WAW_007] Redemarrage de WazuhSvc pour appliquer..."
Restart-Service -Name "WazuhSvc"
Start-Sleep -Seconds 3
$svc = Get-Service -Name "WazuhSvc"
if ($svc.Status -ne "Running") {
    Write-Host "[WAW_007] ERREUR: WazuhSvc n'est pas actif apres redemarrage (statut: $($svc.Status))."
    exit 1
}

Write-Host "[WAW_007] OK. Tout fichier depose dans l'une de ces zones sur CETTE machine declenche desormais une soumission VirusTotal (integration deja active cote manager, WAZ_050) - jamais de fichier .log/.htm/.jpg/.png/.chm/.pnf/.evtx (exclus par defaut)."
exit 0
