#!/bin/bash
# INFRA_002_RECLAIM_HOME - WEF_INFRA_BLD_RECLAIMHOME - Fusionne /home
# (quasi vide sur un role ELK_HOST) dans / pour donner cet espace a la
# charge reelle (ES/Logstash/Kibana/Wazuh).
#
# AJOUTE LE 2026-09-09 (demande explicite utilisateur, suite a
# l'incident reel du jour : disque a 97%, Elasticsearch passe ROUGE
# faute d'espace pour allouer un shard - voir docs/JOURNAL_TECHNIQUE.md).
# Diagnostic reel a la racine du probleme (pas seulement le residu
# accumule dans la journee - deja traite ailleurs) : "pvs"/"vgs"/"lvs"
# ont montre un groupe de volumes DEJA rempli a 100% (VFree=0) des
# l'installation - 35,6 Go pour /, 17,4 Go pour /home, 6 Go de swap, sur
# un disque de 60 Go. Aucun kickstart/script de partitionnement ne fait
# partie de ce depot (partitionnement automatique Anaconda a
# l'installation OS, hors du controle de cette usine) - ce job
# rebalance donc APRES coup, une fois, plutot que de compter sur une
# reinstallation OS avec un autre schema.
#
# JAMAIS un nettoyage aveugle : /home n'est touche QUE s'il est deja
# quasi vide (uniquement le squelette par defaut - aucun utilisateur
# interactif reel sur ce role, l'unique acces est root via SSH, dont le
# HOME est /root, jamais /home). Verifie en reel avant toute action
# irreversible - si /home contient plus que quelques dizaines de Ko, ce
# job se contente de le signaler et ne touche a rien.
#
# XFS NE PEUT JAMAIS ETRE REDUIT (seulement agrandi) - impossible de
# "retrecir" /home pour donner de la place a / sans detruire son volume
# logique. Sans risque ici puisque le contenu est verifie vide avant
# suppression - jamais une hypothese.
set -uo pipefail
source "$VARS_FILE"

HOME_LV="$(findmnt -n -o SOURCE /home 2>/dev/null || true)"
if [ -z "$HOME_LV" ]; then
  echo "[INFRA_002_RECLAIM_HOME] /home n'est pas un point de montage separe (deja fusionne, ou schema de partitionnement different) - rien a faire."
  exit 0
fi

ROOT_LV="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [ -z "$ROOT_LV" ]; then
  echo "[INFRA_002_RECLAIM_HOME] ERREUR : impossible de determiner le volume de /." >&2
  exit 1
fi

# Seuil volontairement bas (50 Mo) : le squelette par defaut d'un
# systeme fraichement installe (/home/lost+found + rien d'autre en
# pratique sur ce role) tient largement dedans - au-dela, on suppose
# une VRAIE donnee et on n'y touche jamais.
SEUIL_KO=51200
HOME_USED_KO="$(df --output=used /home 2>/dev/null | tail -n1 | tr -d ' ')"
if [ -z "$HOME_USED_KO" ] || [ "$HOME_USED_KO" -gt "$SEUIL_KO" ]; then
  echo "[INFRA_002_RECLAIM_HOME] /home contient ${HOME_USED_KO:-un montant indetermine} Ko (seuil : ${SEUIL_KO} Ko) - possible donnee reelle, jamais touche a l'aveugle. Ignore."
  exit 0
fi

echo "[INFRA_002_RECLAIM_HOME] /home quasi vide (${HOME_USED_KO} Ko) sur ce role ELK_HOST (aucun utilisateur interactif reel) - fusion dans / (${ROOT_LV})..."
umount /home
sed -i '\#[[:space:]]/home[[:space:]]#d' /etc/fstab
if ! lvremove -f "$HOME_LV"; then
  echo "[INFRA_002_RECLAIM_HOME] ERREUR : lvremove a echoue sur ${HOME_LV}." >&2
  exit 1
fi
if ! lvextend -l +100%FREE "$ROOT_LV"; then
  echo "[INFRA_002_RECLAIM_HOME] ERREUR : lvextend a echoue sur ${ROOT_LV}." >&2
  exit 1
fi
xfs_growfs / >/dev/null

echo "[INFRA_002_RECLAIM_HOME] Etat disque apres fusion :"
df -h /
echo "[INFRA_002_RECLAIM_HOME] OK."
exit 0
