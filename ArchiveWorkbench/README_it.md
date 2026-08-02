# Mac Unzip

> **Apri qualsiasi archivio. Piega la compressione al tuo volere.**
> Un motore di decompressione dall'anima cyberpunk, forgiato in Swift nativo per il Mac moderno.

[English](README.md) | [中文](README_zh.md) | [Français](README_fr.md) | [Español](README_es.md) | **[Italiano](README_it.md)** | [日本語](README_ja.md) | [한국어](README_ko.md)

---

**Mac Unzip** è un'utilità di archiviazione nativa per macOS, costruita da zero con **Swift 6.2** e **SwiftUI** e ottimizzata per **Apple Silicon**. Apre, crea e protegge archivi in tutti i formati che contano — ZIP, 7z, RAR, TAR, DMG e ISO — senza mai allontanarsi dal Mac di cui ti fidi.

Niente Electron. Nessun runtime esterno. Nessuna telemetria. Solo uno strumento veloce e preciso, che fa una cosa sola, ma la fa straordinariamente bene.

## Funzionalità

### Formati
- **Apertura:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO
- **Creazione:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST
- **Crittografia:** protezione AES-256 per archivi ZIP e 7z

### Flusso di lavoro
- **Trascina e rilascia** gli archivi in un punto qualsiasi della finestra per estrarli o anteprima
- **Estensione Finder Sync** — tasto destro su qualsiasi file o cartella per comprimerlo o aprirlo
- **Anteprima integrata** — visualizza immagini, PDF, video, testo e Markdown senza estrarre l'intero archivio
- **Supporto multi-finestra** per gestire più archivi contemporaneamente
- **Modalità scura / chiara** che segue l'aspetto del sistema

### Sicurezza e affidabilità
- **Estrazione sicura** con protezione da zip-slip e path traversal
- **Rifiuto dei collegamenti simbolici** e budget delle risorse per neutralizzare gli archivi malevoli
- **Journal di ripristino** — le estrazioni interrotte riprendono invece di corrompere i dati
- **Crittografia AES-256** per i tuoi archivi ZIP e 7z più sensibili

## Screenshot

![Mac Unzip](Assets/Logo.svg)

## Installazione

### Requisiti
- **macOS 26** o versione successiva
- Mac con **Apple Silicon** (serie M)
- **Xcode 26** per compilare dai sorgenti

### Compilazione dai sorgenti

```bash
git clone https://github.com/smkzw/Mac-Unzip.git
cd ArchiveWorkbench
xcodegen generate
open MacUnzip.xcodeproj
```

Seleziona lo schema **App**, scegli il dispositivo di destinazione e premi **⌘R** in Xcode 26.

Nella radice del repository è disponibile anche un `MacUnzip-1.0.7.dmg` precompilato per una valutazione rapida.

## Requisiti di sistema

| Componente | Minimo |
| --- | --- |
| Sistema operativo | macOS 26 |
| Architettura | Apple Silicon (arm64) |
| Strumenti di compilazione | Xcode 26, Swift 6.2 |
| Spazio su disco | ~150 MB per l'app |

## Licenza

**L'uso personale è GRATUITO.** L'uso commerciale o aziendale richiede una licenza a pagamento.

- Uso personale, didattico e open source non commerciale — gratuito
- Uso aziendale, da freelance, per clienti o a scopo di lucro — [licenza a pagamento richiesta](LICENSE)

Consulta il file [LICENSE](LICENSE) per i termini completi.

---

© 2026 smkzw. Tutti i diritti riservati.
