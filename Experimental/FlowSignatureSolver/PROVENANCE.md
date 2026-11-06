# Provenance and modifications

Reviewed source revision: YouTubeKit `7f75a2299dc329c0b7855afb25d47663a02855cb`.

Swift adapter derives its batch protocol/resource-loading design from:
https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/SignatureSolver.swift
MIT copyright 2022 Alexander Eichhorn; full notice in THIRD_PARTY_NOTICES.txt.

Modifications: separate dormant package, explicit opt-in and fixture allowlist, input/result
bounds, pinned helper hashes, actor serialization, fresh VM, strict exception/result checks,
no raw exception logging, and no playback/network integration. Original broad environment
stubs were omitted; only the pinned helper's own setupNodes are used. Unsupported player
assumptions must produce an error. Execution time and heap use remain unbounded.

## Resources

Copied as text from these exact immutable repository resources; only final newline normalization
may differ. Original blob IDs are below; SHA-256 checks in the adapter match the shipped bytes.
No parser or helper was executed while preparing this package.

- meriyah.umd.js: original Git blob eeac5d8b20e0b7e628fe8011d4e0a8b2d095dbec
  https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/Resources/meriyah.umd.js
- astring.umd.js: original Git blob 74fe24e41ff8db4b4f62df7759ffa76e46d262b4
  https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/Resources/astring.umd.js
- yt_ejs_helper.js: original Git blob bbf5555dbff8ff26ad6a21932426168060481b28
  https://github.com/alexeichhorn/YouTubeKit/blob/7f75a2299dc329c0b7855afb25d47663a02855cb/Sources/YouTubeKit/Resources/yt_ejs_helper.js

Meriyah identifies its version as 6.1.4. ISC notice verified at the v6.1.4 tag.
Astring's exact upstream release is not identified in this copied bundle; its precise bytes
are identified by the immutable YouTubeKit Git blob above. The copyright-2015 David Bonnet
MIT license is preserved from the upstream license blob `4714dd6f96e1fbdb0dc21b86032c665408a49741`.
The generated EJS helper explicitly carries SPDX Unlicense; the full EJS project notice is
preserved. No representation is made that these are the latest parser/helper releases.

This does not relicense third-party resources as GPL. Their original permissive notices
remain, while the modified Swift adapter and surrounding Flow port are GPL-3.0-only.

