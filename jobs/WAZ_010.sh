#!/bin/bash
# WAZ_010 - WEF_WAZ_BLD_INDXRINSTLL - Installation de wazuh-indexer
# Version pilotee par WAZ_PACKAGE_VERSION dans vars.conf (vide = derniere
# version disponible dans le depot WAZUH_REPO_MAJOR). Wazuh recommande de
# garder indexer/manager/dashboard sur la MEME version - un seul reglage
# WAZ_PACKAGE_VERSION couvre les 3 (WAZ_010/011/012). Ne change jamais
# une version deja en place, seulement au premier passage.
set -uo pipefail
source "$VARS_FILE"

# CORRIGE LE 2026-08-12 (meme bug/correctif que ES_017) : verifier via
# le code de retour de "rpm -q", pas via le contenu de "--qf" qui peut
# porter un message localise "paquet absent" capture comme version.
#
# CORRECTIF 2026-08-19 (incident reel wef-elk-core) : "dnf install -y"
# n'etait jamais verifie - meme famille d'echec silencieux que les
# incidents 4/107 plus haut. Constate en reel : DNS intermittent sur la
# VM (packages.wazuh.com injoignable par moments, "Could not resolve
# host", confirme aussi par un `ping google.com` qui echouait juste
# apres qu'un `getent hosts` ait reussi - probleme reseau de la machine,
# hors de portee d'un correctif de script) a fait echouer dnf, mais le
# job affichait quand meme "[WAZ_010] OK." - la vraie erreur n'apparaissait
# alors que 4 jobs plus loin, sur WAZ_014 ("Unit wazuh-indexer.service
# not found"), sans lien evident avec sa cause reelle. Corrige : code de
# sortie de dnf verifie ET presence reelle confirmee par rpm -q apres
# coup (double verification, meme idiome que les jobs deja renforces
# ailleurs dans ce projet) - le job echoue desormais bruyamment, tout de
# suite, avec le vrai message dnf visible dans son propre log.
if rpm -q wazuh-indexer &>/dev/null; then
  INSTALLED_VER=$(rpm -q --qf '%{VERSION}' wazuh-indexer 2>/dev/null)
  if [ -z "${WAZ_PACKAGE_VERSION:-}" ] || [ "$INSTALLED_VER" = "${WAZ_PACKAGE_VERSION}" ]; then
    echo "[WAZ_010] Deja installe (version ${INSTALLED_VER}), ignore."
  else
    echo "[WAZ_010] AVERTISSEMENT : version installee (${INSTALLED_VER}) differente de WAZ_PACKAGE_VERSION (${WAZ_PACKAGE_VERSION}). Pas de changement automatique - desinstallez manuellement si besoin."
  fi
  echo "[WAZ_010] OK."
  exit 0
fi

PKG_SPEC="wazuh-indexer${WAZ_PACKAGE_VERSION:+-${WAZ_PACKAGE_VERSION}}"
echo "[WAZ_010] Installation de ${PKG_SPEC}..."
if ! dnf install -y "$PKG_SPEC"; then
  # CORRECTIF 2026-08-19 (2e incident reel le meme jour, wef-elk-core) :
  # le premier echec dnf peut venir d'un IPv6 casse (frequent sur un
  # partage de connexion telephone/hotspot) plutot que d'un vrai probleme
  # DNS - constate en reel : dig/getent resolvaient packages.wazuh.com
  # sans probleme (requetes DNS brutes, jamais IPv6), mais dnf echouait
  # quand meme avec "Could not resolve host name" via libcurl, qui tente
  # une resolution/connexion IPv6 des qu'une adresse IPv6 (meme locale,
  # non fonctionnelle) est presente sur l'interface. --setopt=ip_resolve=4
  # force dnf a ignorer l'IPv6 - a reessayer automatiquement UNE fois
  # avant d'abandonner, jamais impose d'emblee pour ne pas ralentir un
  # reseau IPv6 qui fonctionne correctement ailleurs.
  echo "[WAZ_010] AVERTISSEMENT : dnf install a echoue, nouvel essai en forcant l'IPv4 (--setopt=ip_resolve=4, cas connu : IPv6 casse sur certains reseaux/hotspots)..."
  DNF_OUT2="$(dnf install -y --setopt=ip_resolve=4 "$PKG_SPEC" 2>&1)"
  DNF_RC2=$?
  echo "$DNF_OUT2"
  if [ "$DNF_RC2" -ne 0 ]; then
    # CORRECTIF 2026-09-03 (incident reel, deploiement VM ELK_HOST Oracle
    # Linux 8) : echec distinct des deux precedents, rien a voir avec le
    # reseau/DNS/IPv6 - "Erreur de la transaction de test" avec une
    # longue liste de fichiers /usr/lib/.build-id/xx/... "entre en
    # conflit avec le fichier du paquet logstash". Cause reelle : Wazuh
    # Indexer et Logstash embarquent chacun leur propre JVM (OpenJDK)
    # dans leur paquet ; quand les deux paquets embarquent par coincidence
    # exactement la meme version d'OpenJDK, RPM genere pour chacun un lien
    # de debogage /usr/lib/.build-id/<hash>/... au MEME chemin (le hash
    # depend du binaire JVM, identique puisque meme version) mais pointant
    # vers l'installation de CHAQUE paquet (/usr/share/logstash/jdk/...
    # vs /usr/share/wazuh-indexer/jdk/...) - RPM refuse par prudence
    # qu'un second paquet ecrase un fichier deja possede par un autre.
    # Ces liens ne sont que des metadonnees de debogage (utilisees par des
    # outils d'analyse de crash), jamais executees ni chargees au
    # demarrage - les remplacer n'affecte en rien le fonctionnement reel
    # de Logstash ou de Wazuh Indexer, seulement la capacite a deboguer
    # un eventuel crash natif de l'un des deux avec le binaire de l'autre
    # (cas marginal, jamais rencontre sur ce projet). Corrige, en dernier
    # recours et seulement quand la signature exacte du conflit
    # (chemin non traduit, donc fiable independamment de la langue du
    # systeme) est reconnue : installation directe du paquet deja mis en
    # cache par dnf via "rpm --replacefiles", qui autorise explicitement
    # ce remplacement au lieu du refus par defaut de dnf.
    # Honnetete sur la certitude de ce correctif : bonne comprehension du
    # mecanisme RPM et des paquets concernes, pas verifiee sur toutes les
    # combinaisons de versions Logstash/Wazuh Indexer possibles - a
    # surveiller si une machine future presente un conflit .build-id avec
    # un AUTRE paquet que logstash.
    if echo "$DNF_OUT2" | grep -q '/usr/lib/\.build-id/'; then
      echo "[WAZ_010] AVERTISSEMENT : conflit detecte sur des liens de debogage /usr/lib/.build-id/ (JVM embarquee partagee avec un autre paquet Elastic/Wazuh deja installe) - tentative de contournement via rpm --replacefiles sur le paquet deja mis en cache..."
      CACHED_RPM="$(find /var/cache/dnf -name "${PKG_SPEC}-*.rpm" 2>/dev/null | head -1)"
      if [ -z "$CACHED_RPM" ]; then
        echo "[WAZ_010] ERREUR : conflit .build-id detecte mais aucun paquet mis en cache trouve sous /var/cache/dnf (nom recherche : ${PKG_SPEC}-*.rpm) - impossible de tenter le contournement." >&2
        exit 1
      fi
      echo "[WAZ_010] Paquet en cache trouve : ${CACHED_RPM} - installation directe (rpm -Uvh --replacefiles)..."
      if ! rpm -Uvh --replacefiles "$CACHED_RPM"; then
        echo "[WAZ_010] ERREUR : rpm --replacefiles a lui aussi echoue, voir le message rpm ci-dessus." >&2
        exit 1
      fi
    else
      echo "[WAZ_010] ERREUR : dnf install a echoue meme en IPv4 force (voir le message dnf ci-dessus, souvent un depot injoignable/DNS)." >&2
      exit 1
    fi
  fi
fi
if ! rpm -q wazuh-indexer &>/dev/null; then
  echo "[WAZ_010] ERREUR : dnf s'est termine sans erreur mais wazuh-indexer n'est toujours pas installe (verification rpm -q)." >&2
  exit 1
fi
echo "[WAZ_010] OK (confirme installe par rpm -q)."
exit 0
