# Revisione AirCard-iOS

Repository: `Mak5er/AirCard-iOS`, commit studiato
`097a058c984ffc33ccb697b9dfe8058be3e86244`.

Elementi rilevanti:

- `PairingController.swift` avvia un host RPPairing, pubblica Bonjour
  `_remotepairing-pairable-host._tcp` e conserva il pairing plist.
- `AirliftFFI` espone `al_pairing_run_host` e `al_exploit_write_dir`; il core Rust
  usa il servizio AirTraffic attraverso un tunnel locale/RSD.
- Per Wallet, upstream genera varianti PNG 1536×969 (@3x) e 1024×646 (@2x), più
  PDF per alcuni pass transit, quindi scrive in
  `/var/mobile/Library/Passes/Cards/<id>.pkpass`.
- Dopo la scrittura invalida best-effort `FrontFace`, `Preview` e `PlaceHolder`
  nelle directory `.cache` e `.pkcache`.
- Il README upstream dichiara iOS 27+, LocalDevVPN e pairing Developer Mode.
  Il deployment target Xcode (18.0) non equivale alla compatibilità runtime.
- Il framework include slice arm64 device e arm64 simulator, e collega C++.
- La licenza è MIT, copyright 2026 Johnny Franks. La redistribuzione richiede
  mantenimento di copyright, permission notice e disclaimer.

Decisione POC: inclusione del minimo necessario, niente UI/theme/poster code,
attribuzione completa, apply reale tramite la stessa FFI upstream e una piccola
estensione `al_exploit_read_file` per backup/restore. L'estensione riusa il
trasferimento AirTraffic già usato dal canary upstream, ma richiede validazione
fisica prima della distribuzione.
