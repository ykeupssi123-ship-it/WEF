Ce dossier est livre VOLONTAIREMENT VIDE (a part ce fichier).

Il existe pour que vous n'ayez PAS a le recreer (mkdir) a chaque
deploiement/mise a jour - seule la commande ci-dessous reste a taper,
une fois par machine, pour activer l'alerte email sur echec de job
(notifier.sh) :

  echo 'votre_mot_de_passe' > secrets/smtp_password.txt
  chmod 600 secrets/smtp_password.txt

Rien d'autre a faire : vars.conf pointe deja SMTP_PASS_FILE vers
secrets/smtp_password.txt par defaut (section "ALERTE PAR EMAIL SUR
ECHEC DE JOB"). Il ne reste qu'a renseigner NOTIF_ENABLED/SMTP_HOST/
SMTP_USER/NOTIF_FROM/NOTIF_TO dans vars.conf si ce n'est pas deja fait.

AJOUTE LE 2026-08-30, suite a l'audit reel de la reprise WAZ_020_VERIFY
(4 mots de passe trouves EN CLAIR dans vars.conf, dont le mot de passe
root reel des VM de l'usine) - 4 fichiers de plus suivent maintenant la
meme regle que smtp_password.txt :

  secrets/wazuh_indexer_admin_password.txt
    Mot de passe admin de wazuh-indexer (WAZ_INDEXER_ADMIN_PASSWORD_FILE).
    Secret INTERNE a l'usine : si absent, WAZ_014A_INDXR_ADMINPW.sh en
    genere un automatiquement (conforme a la politique de mot de passe
    Wazuh) et l'ecrit ici tout seul - RIEN A FAIRE pour un depot a froid.
    C'est aussi le mot de passe humain de connexion a Wazuh Dashboard
    (mode KIBANA_AUTH_MODE=internal) : consultez ce fichier apres le
    premier passage de l'orchestrateur si vous devez vous connecter.

  secrets/wazuh_api_password.txt
    Mot de passe du compte API Wazuh (WAZ_API_PASSWORD_FILE, utilisateur
    WAZ_API_USER). Secret INTERNE a l'usine, meme regle que ci-dessus :
    absent -> genere automatiquement au bon moment de la chaine.

  secrets/factory_ssh_password.txt
    Mot de passe SSH de secours pour DIST_001.sh (distribution de la CA
    vers BEATS_HOST, VM2 uniquement). Secret EXTERNE au sens ou il
    identifie un compte SSH deja existant sur une autre machine : PAS
    genere automatiquement. A deposer vous-meme, UNIQUEMENT sur VM2,
    UNIQUEMENT si vous n'utilisez pas FACTORY_SSH_KEY (une cle SSH reste
    preferable). Ne remplissez jamais ce fichier sur VM1 (ELK_HOST).

  secrets/ldap_bind_password.txt
    Mot de passe du compte de service Active Directory (LDAP_BIND_PASSWORD_FILE,
    utilise uniquement si KIBANA_AUTH_MODE=ldap). Secret EXTERNE (compte
    AD du client) : PAS genere automatiquement, fourni par
    l'administrateur AD du client. Sans objet si KIBANA_AUTH_MODE reste
    a "internal" (valeur par defaut).

REGLE DE SECURITE (ne jamais enfreindre) : aucun vrai mot de passe ne
doit jamais se trouver dans ce dossier au moment ou une archive de
livraison est construite. Le processus de build verifie explicitement
que ce dossier ne contient QUE ce fichier README avant chaque livraison
- si vous avez deja mis un vrai mot de passe ici sur votre machine de
travail, ne livrez jamais ce dossier tel quel a un tiers.
