# Claude Usage — widget de barre de menu macOS

Petite app macOS (Swift, un seul fichier, sans dépendance) qui affiche dans la barre de menu l'usage de ta limite **hebdomadaire** Claude, ainsi que celui de la **session de 5 h**.

- Dans la barre de menu : `7j 42%` (orange à partir de 80 %, rouge à partir de 90 %).
- Au clic : une barre de progression par limite, colorée selon le niveau (vert < 50 %, jaune < 80 %, orange < 90 %, rouge ≥ 90 %), et le temps restant avant le reset.
- Notifications macOS à **50 %, 80 %, 90 % et 95 %**, pour la limite hebdo et pour la session de 5 h (une alerte par seuil et par période).
- Rafraîchissement toutes les 5 minutes et au réveil du Mac.

## Prérequis

- macOS avec les outils de compilation Xcode : `xcode-select --install`
- [Claude Code](https://claude.com/claude-code) installé et **connecté** (lance `claude` au moins une fois). L'app réutilise son token OAuth, stocké dans le Keychain.

## Installation

```sh
git clone https://github.com/myrmexena/widget-claude-usage.git
cd widget-claude-usage
./build.sh
cp -R ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

Au premier lancement :

1. macOS peut demander l'accès au Keychain (« Claude Code-credentials ») : choisis **Toujours autoriser**.
2. macOS demande l'autorisation d'envoyer des notifications : accepte. Pour que les alertes restent affichées, choisis le style **Alertes** (et non « Bannières ») dans Réglages Système → Notifications → ClaudeUsage.

### Lancement au démarrage

Réglages Système → Général → Ouverture → **+** → sélectionne `ClaudeUsage.app`.

### Mise à jour

```sh
git pull
pkill ClaudeUsage
./build.sh
rm -rf /Applications/ClaudeUsage.app && cp -R ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

## Installer sur un autre Mac

Le plus simple est de recompiler sur place (voir ci-dessus). Si tu copies l'app déjà compilée, elle n'est signée qu'en ad hoc et macOS la bloque après un transfert : retire la quarantaine avec

```sh
xattr -dr com.apple.quarantine /Applications/ClaudeUsage.app
```

Le binaire est compilé pour l'architecture de la machine d'origine (Apple Silicon ou Intel).

## Fonctionnement

L'app lit le token dans le Keychain (`security find-generic-password -s "Claude Code-credentials"`) et interroge `https://api.anthropic.com/api/oauth/usage`, le même endpoint que la commande `/usage` de Claude Code.

> ⚠️ Cet endpoint n'est **pas documenté** : Anthropic peut le modifier ou le retirer sans préavis.

## Dépannage

| Symptôme | Cause / solution |
| --- | --- |
| Menu : « Token introuvable » | Claude Code n'est pas connecté : lance `claude` et connecte-toi. |
| Menu : « Token expiré » | Relance `claude` pour renouveler le token. |
| Affiche `7j ⚠︎` | Voir le message d'erreur en haut du menu (réseau, HTTP…). |
| Pas de notification | Vérifie Réglages Système → Notifications → ClaudeUsage et les modes Concentration. |

## Arrêter / désinstaller

Menu → **Quitter**, puis supprime `/Applications/ClaudeUsage.app` et retire-la des éléments d'ouverture.
