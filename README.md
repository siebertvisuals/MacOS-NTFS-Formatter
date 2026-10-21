# NTFS Formatter pour macOS

Une app à fenêtre unique pour formater un disque externe ou une clé USB (exFAT, FAT32…) en **NTFS** depuis un Mac.
Tout est inclus dans l'app : **rien à installer** (ni Homebrew, ni Terminal).

## Pour les utilisateurs

1. Télécharge `NTFSFormatter.zip` (onglet *Releases*), double-clique pour le décompresser.
2. Glisse **NTFSFormatter** dans le dossier *Applications*.
3. **Premier lancement** : l'app n'est pas signée par Apple, macOS la bloque une première fois.
   - Double-clique sur l'app : un message d'avertissement apparaît, ferme-le.
   - Ouvre **Réglages Système → Confidentialité et sécurité**, descends en bas de la page,
     clique sur **Ouvrir quand même** à côté de « NTFSFormatter », puis saisis ton mot de passe.
   - Cette étape n'est à faire qu'une seule fois.
4. Branche ton disque, choisis-le dans la liste, clique sur **Formater en NTFS…** et confirme.

> ⚠️ **Tout le contenu du disque est effacé**, partitions comprises. C'est irréversible.
> Seuls les disques externes sont proposés : le disque de ton Mac n'apparaît jamais.

## À savoir

- macOS monte le NTFS en **lecture seule**. Le disque est destiné à Windows ; pour y écrire depuis le Mac,
  il faut un pilote tiers (Paragon, Tuxera, iBoysoft, ou ntfs-3g avec macFUSE).
- Cette version est pour **Mac Apple Silicon** (M1 et plus récents), macOS 13 ou plus.
- Fourni tel quel, sans garantie.

## Pour les développeurs

```bash
brew install ntfs-3g-mac     # source de mkntfs, copié dans l'app par build.sh
xcode-select --install       # compilateur Swift
./build.sh                   # produit NTFSFormatter.app et NTFSFormatter.zip
```

`build.sh` embarque `mkntfs` et ses bibliothèques dans `Contents/Resources/ntfs` et réécrit leurs chemins.
L'app lance ensuite le formatage via la fenêtre de mot de passe système (`osascript … with administrator privileges`).

Une version en ligne de commande existe aussi : `format_ntfs.sh`.

## Licences

Le code de cette app (interface Swift, scripts) est sous **licence MIT** : voir [LICENSE](LICENSE).

L'app embarque des composants tiers, qui gardent leur propre licence :
`mkntfs` / `libntfs-3g` (NTFS-3G) sous **GPL v2**, et `libintl` (gettext) sous **LGPL**.
Leurs textes sont dans `NTFSFormatter.app/Contents/Resources/licenses/`.
Code source de NTFS-3G : <https://github.com/tuxera/ntfs-3g>.
