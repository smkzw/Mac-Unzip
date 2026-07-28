# Mac Unzip - International Launch Kit

## Show HN (Hacker News)

Title: Show HN: Mac Unzip – A native macOS archive utility built in Swift 6.2

Body:
I built a native macOS archive utility because I was tired of Electron-based tools that take 3 seconds to open a ZIP file.

Mac Unzip is written entirely in Swift 6.2 + SwiftUI, targeting Apple Silicon. It handles ZIP, 7z, RAR, TAR.*, DMG, and ISO formats.

Security was the primary design constraint:
- Every extraction goes through a secure materializer that opens files with O_NOFOLLOW and O_EXCL
- External binaries (7zz, rar) are SHA-256 verified before every single spawn
- Passwords are mlock'd and zeroized, never touching swap
- Path traversal is structurally impossible (fd-rooted, not string-based)
- Saves are journal-backed and atomic (crash mid-write = graceful recovery)

It also has in-app preview (images, PDF, video, Markdown) without full extraction, a Finder Sync extension for right-click compress/extract, and one-click "set as default handler".

Open source: https://github.com/smkzw/Mac-Unzip

Happy to answer questions about the security architecture or Swift 6 concurrency patterns.

---

## Reddit r/macapps

Title: [Free] Mac Unzip – Native macOS archive utility (ZIP/7z/RAR/TAR/DMG/ISO) with AES-256 and in-app preview

Body:
Hey r/macapps,

I built Mac Unzip (Mac解霸) because The Unarchiver hasn't been updated in ages and Keka costs money for basic features.

What it does:
- Opens ZIP, 7z, RAR, TAR.GZ/XZ/ZST, DMG, ISO
- Creates ZIP, 7z, RAR, TAR archives with optional AES-256 encryption
- Previews files in-app (images, PDF, video, code) without extracting
- Finder right-click integration (compress/extract)
- Set as default archive handler in one click

What makes it different:
- 100% native Swift/SwiftUI (no Electron, ~15MB total)
- Security-first: path traversal defense, symlink rejection, binary integrity checks
- Crash-proof: journal-backed atomic saves
- Apple Silicon optimized

Requirements: macOS 26+, Apple Silicon

Download: https://github.com/smkzw/Mac-Unzip/releases

Free for personal use. Feedback welcome!

---

## Product Hunt

Tagline: The native macOS archive utility that treats security as a feature, not an afterthought.

Description:
Mac Unzip handles 40+ archive formats (ZIP, 7z, RAR, TAR, DMG, ISO) with a security architecture that would make a paranoid sysadmin smile. Every file operation uses O_NOFOLLOW. Every external binary is SHA-256 verified before spawn. Every save is atomic and journal-backed.

Built in Swift 6.2 + SwiftUI for Apple Silicon. No Electron. No web views. Just fast, secure archive management with in-app preview, Finder integration, and AES-256 encryption.

---

## AlternativeTo

Name: Mac Unzip
Platforms: macOS (Apple Silicon)
License: Free (personal), Paid (commercial)
Tags: archive, zip, 7zip, rar, extraction, compression, security, native, swift

Description: Native macOS archive utility supporting ZIP, 7z, RAR, TAR, DMG, ISO with AES-256 encryption, secure extraction (path traversal defense, symlink rejection), in-app file preview, Finder integration, and crash-recovery journaling. Built in Swift 6.2 for Apple Silicon.

---

## Posting Checklist

- [ ] Show HN (post Tuesday-Thursday, 8-10am ET for max visibility)
- [ ] Reddit r/macapps (weekends get more engagement)
- [ ] Product Hunt (schedule for Tuesday/Wednesday, line up 5+ hunter upvotes)
- [ ] AlternativeTo.net (submit as alternative to The Unarchiver, Keka, BetterZip)
- [ ] MacUpdate.com (submit listing)
- [ ] Twitter/X: post with #macOS #AppleSilicon #OpenSource tags, tag @Apple
- [ ] V2EX (Chinese developer community): 分享创造 node
