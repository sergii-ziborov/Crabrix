# Shared modal actions — 25 October 2026

The extra bordered style on the Project settings close control nested a second
surface inside the system toolbar. All custom modal headers now share
`CrabrixModalCloseAction`: a plain X at the trailing edge, primary foreground,
an accessible Close label, and no separate border or background.

The eleven uses cover Project settings, the My Projects metadata editor,
New Project, New File/Folder, GitHub import, Cargo packages, package preparation,
package storage, compiler help, practice and the Game Center sign-in wrapper.
Utility controls such as keyboard dismissal and catalog sorting occupy the
leading edge where necessary.

Both metadata editors share `CrabrixModalSaveButton`, a prominent blue Save
with a contrasting label at the leading edge. Existing empty-name validation,
pending-save disabling, durable writes and failed-save draft retention remain.
Closing package progress continues to leave downloads running.

The optimized simulator app build passed with SDK 27.1 RC. Native visual
inspection was unavailable while the Mac was locked; no screenshot-based
verification is claimed. Existing editor controls, Duo fold sizing, build tabs,
keyboard helpers, compiler/runtime settings and website sources were unchanged.

A follow-up visual attempt on October 26 reached the Xcode 27.1 RC Device Hub application, but the native UI tool could not read its window (AX cannot complete). No visual success is inferred from that attempt; source/build verification and the delivered build 93 status remain as recorded above.
