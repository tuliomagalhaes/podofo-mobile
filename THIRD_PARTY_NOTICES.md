# Third-party notices

The generated static archive combines the following source packages. Their
complete source archives and the builder patches are included in the generated
`artifacts/podofo-ios-1.1.0-corresponding-source.tar.gz` bundle.

| Component | Version | SPDX expression | Source |
| --- | --- | --- | --- |
| PoDoFo | 1.1.0 | LGPL-2.0-or-later | https://github.com/podofo/podofo |
| OpenSSL | 1.1.1w | OpenSSL | https://www.openssl.org/source/ |
| FreeType | 2.13.2 | FTL OR GPL-2.0-or-later | https://freetype.org/ |
| libxml2 | 2.12.9 | MIT | https://gitlab.gnome.org/GNOME/libxml2 |

PoDoFo 1.1.0 bundles third-party sources. The build extracts the complete
PoDoFo notice set into `artifacts/notices/podofo-notices.txt`, including the
top-level LGPL/MPL/NOTICE material; the AFDKO, Chromium numerics, and PDFium
notices used by the bundled source tree; and the Foxit and LiberaLean
standard-font notices embedded in the compiled library. It also extracts the
complete OpenSSL, FreeType, and libxml2 notices into separate hash-recorded
files.

`artifacts/podofo-ios-1.1.0-corresponding-source.tar.gz` is constructed with
sorted file names and normalized gzip/tar timestamps, owner, and group fields.
It contains the downloaded source archives, build recipes, patches, and this
notice index. The source archives themselves retain their upstream bytes and
are verified by SHA-256 before inclusion.
