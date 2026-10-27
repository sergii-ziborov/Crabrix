# Temporary Playground privacy implementation

- The browser editor is public; no app or website account is needed.
- Source is encrypted with AES-256-GCM on participants’ devices. The key and bearer capability are in the URL fragment; the relay never receives the key.
- The relay stores bounded ciphertext and transient presence only in process memory, for the creator-selected expiry up to 24 hours. It has no account/SQL/file/backup integration. Restart can end sessions early.
- API access logging and proxy caching/buffering are disabled for `/api/playground/`. Normal website access logs follow the existing website policy.
- Source execution occurs in the native local WASI runtime or a browser Worker. Received code never runs automatically. No backend compiler or shell is supplied.
- Guest limits: four participants, 16 text files, 64 KiB per file and 128 KiB total. Packages, images and generated binaries are excluded from the source-sharing document.
- Save/download creates a separate local copy that remains after link expiry. No account project library was introduced.
- Privacy/Terms copies match canonical site documents and bundled offline app documents; original new editor/runtime notices are included.

Build 103 retains no tracking, advertising or analytics SDK. The optional sharing operation and temporary encrypted relay are explicitly described in App Review notes and Privacy/Terms. App Privacy web questionnaire was not re-read with the API key: those fields are not exposed through that API. The encrypted relay does not obtain readable user source.

References: [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) and the versioned Privacy/Terms implementation; this record states the implementation, not an assurance of App Review approval.
