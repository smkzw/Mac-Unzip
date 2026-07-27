# ArchiveWorkbench License

> **STATUS: TBD** - The license for ArchiveWorkbench itself has not yet been
> determined by the author. This file is a placeholder to be finalized before
> public distribution.

Copyright (c) 2026 smkzw. All rights reserved.

---

## License Decision Notes

When choosing a license for ArchiveWorkbench, consider the following
third-party compatibility constraints:

### Bundled / Linked Dependencies (affect license choice)

| Component | License | Commercial Use | Implications |
|-----------|---------|----------------|--------------|
| minizip-ng 4.2.1 | Zlib | Permitted | Permissive; no copyleft. Compatible with any license. |
| libarchive 3.8.8 | BSD-2-Clause | Permitted | Permissive; no copyleft. Compatible with any license. |
| Apple libcompression | Apple SDK | Permitted (on Apple HW) | Proprietary; no redistribution needed (part of macOS). |

### External / Optional Dependencies (do NOT affect license choice)

| Component | License | Bundled? | Implications |
|-----------|---------|----------|--------------|
| 7zz 26.02 | LGPL-2.1-or-later | **No** | Not linked, not bundled. Only invoked if user-installed. No LGPL obligations triggered. |

### Summary

- **minizip-ng (Zlib)** and **libarchive (BSD-2-Clause)** both allow
  commercial use, modification, and redistribution with minimal conditions
  (retain copyright notice). They are compatible with proprietary, MIT,
  BSD, Apache-2.0, GPL, or any other license choice.

- **7zz (LGPL-2.1)** is NOT bundled, linked, or distributed with
  ArchiveWorkbench. It is an optional external tool that the user may
  install independently. ArchiveWorkbench merely invokes it via a subprocess
  call (`Process()`). This does not create a derivative work or combined
  work under LGPL, so no LGPL source-disclosure or linking obligations apply.

- **Apple libcompression** is part of macOS and requires no separate
  distribution or license grant from ArchiveWorkbench.

---

## Third-Party Attribution

Regardless of the license chosen for ArchiveWorkbench, the following
attributions must be included in distributions:

1. **minizip-ng**: Retain the Zlib license notice (see THIRD_PARTY_NOTICES.md)
2. **libarchive**: Retain the BSD-2-Clause copyright notice (see THIRD_PARTY_NOTICES.md)

---

## TODO

- [ ] Author selects license (proprietary, MIT, Apache-2.0, etc.)
- [ ] Replace this placeholder with final license text
- [ ] Update SBOM.spdx.json `licenseConcluded` field for ArchiveWorkbench package
- [ ] Add LICENSE file to DMG / distribution package

---

*Generated: 2026-07-27 | ArchiveWorkbench Distribution Preparation (Phase G)*
