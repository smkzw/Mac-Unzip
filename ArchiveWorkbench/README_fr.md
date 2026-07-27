# Mac Unzip

> **Ouvrez n'importe quelle archive. Domptez la compression.**
> Un moteur de décompression à l'esthétique cyberpunk, forgé en Swift natif pour le Mac moderne.

[English](README.md) | [中文](README_zh.md) | **[Français](README_fr.md)** | [Español](README_es.md) | [Italiano](README_it.md) | [日本語](README_ja.md) | [한국어](README_ko.md)

---

**Mac Unzip** est un utilitaire d'archives natif pour macOS, conçu de A à Z avec **Swift 6.2** et **SwiftUI**, et optimisé pour les puces **Apple Silicon**. Il ouvre, crée et sécurise des archives dans tous les formats qui comptent — ZIP, 7z, RAR, TAR, DMG et ISO — sans jamais quitter le Mac auquel vous faites confiance.

Pas d'Electron. Pas d'environnement d'exécution tiers. Pas de télémétrie. Un outil rapide et précis, qui fait une seule chose, mais qui la fait remarquablement bien.

## Fonctionnalités

### Formats
- **Ouverture :** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO
- **Création :** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST
- **Chiffrement :** protection AES-256 pour les archives ZIP et 7z

### Flux de travail
- **Glisser-déposer** : déposez une archive n'importe où dans la fenêtre pour l'extraire ou la prévisualiser
- **Extension Finder Sync** — un clic droit sur un fichier ou un dossier suffit pour le compresser ou l'ouvrir
- **Aperçu intégré** — consultez images, PDF, vidéos, texte et Markdown sans extraire toute l'archive
- **Multi-fenêtres** pour manipuler plusieurs archives en parallèle
- **Mode sombre / clair** aligné sur l'apparence du système

### Sécurité et fiabilité
- **Extraction sécurisée** avec protection contre la traversée de chemins (zip-slip)
- **Rejet des liens symboliques** et budgets de ressources pour neutraliser les archives malveillantes
- **Journal de récupération** — les extractions interrompues reprennent au lieu de corrompre vos données
- **Chiffrement AES-256** pour vos archives ZIP et 7z sensibles

## Captures d'écran

![Mac Unzip](Assets/Logo.svg)

## Installation

### Prérequis
- **macOS 26** ou version ultérieure
- Mac équipé d'une puce **Apple Silicon** (série M)
- **Xcode 26** pour compiler depuis les sources

### Compilation depuis les sources

```bash
git clone https://github.com/smkzw/ArchiveWorkbench.git
cd ArchiveWorkbench
open ArchiveWorkbench.xcodeproj
```

Sélectionnez le schéma **App**, choisissez votre appareil cible, puis appuyez sur **⌘R** dans Xcode 26.

Une image `ArchiveWorkbench-1.0.dmg` précompilée est également disponible à la racine du dépôt pour une évaluation rapide.

## Configuration requise

| Composant | Minimum |
| --- | --- |
| Système d'exploitation | macOS 26 |
| Architecture | Apple Silicon (arm64) |
| Outils de compilation | Xcode 26, Swift 6.2 |
| Espace disque | ~150 Mo pour l'application |

## Licence

**L'usage personnel est GRATUIT.** Toute utilisation commerciale ou en entreprise nécessite une licence payante.

- Usage personnel, éducatif et open source non commercial — gratuit
- Usage en entreprise, en freelance, pour des clients ou à des fins lucratives — [licence payante requise](LICENSE)

Consultez le fichier [LICENSE](LICENSE) pour les conditions complètes.

---

© 2026 smkzw. Tous droits réservés.
