# Wallet Skins POC

Primo POC del round-trip **Safari/PWA → deep link SkinBridge → executor locale → callback Safari**.
Non include marketplace, AI, pagamenti o raccolta di credenziali di pagamento.

La versione corrente include una **demo guidata solo web** da pubblicare su un
server HTTPS e provare subito da Safari su iPhone. Simula l'executor e dichiara
sempre che Wallet non viene modificato.

## Avvio immediato

Requisiti locali: Node.js 20+. La build iOS reale usa Xcode 27 e XcodeGen sul
runner GitHub incluso; l'utente finale non deve avere un Mac o un PC.

```sh
npm test
npm run dev
```

Aprire `http://localhost:8787`. Nel simulatore iOS, generare il progetto mock:

```sh
cd SkinBridge-iOS
xcodegen generate --spec project.yml
open SkinBridge.xcodeproj
```

Perché il simulatore possa raggiungere l'API, lasciare `PUBLIC_BASE_URL` al valore
`http://localhost:8787`. Premendo **Crea job e apri SkinBridge**, Safari invia un
job, apre `skinbridge://`, l'helper verifica firma e scadenza, esegue il mock,
invia il risultato e riapre la pagina callback.

## Configurazione su iPhone

`localhost` sull'iPhone indica l'iPhone stesso. Esporre quindi l'API via HTTPS
su un host raggiungibile e avviarla così:

```sh
PUBLIC_BASE_URL=https://poc.example.test \
WEB_CALLBACK_URL=https://poc.example.test/callback.html \
JOB_SIGNING_PRIVATE_KEY='-----BEGIN PRIVATE KEY----- ...' \
npm run dev
```

La chiave privata inclusa è esclusivamente di sviluppo. Prima di qualsiasi test
condiviso va sostituita e la nuova chiave pubblica va inserita in
`JobVerifier.swift`.

Per il percorso più semplice su un server sono già inclusi Docker, Compose e
Caddy con HTTPS automatico. Seguire `docs/DEPLOY_SERVER.md`, quindi aprire il
dominio da iPhone e scegliere **Prova la demo guidata**. Il percorso
**Configura SkinBridge** diventa utilizzabile quando viene configurato un link
TestFlight, un'IPA firmata oppure l'IPA non firmata per SideStore.

In alternativa, una IPA già firmata può essere pubblicata in `downloads/` e
indicata con `SKINBRIDGE_IPA_URL`: il server genera automaticamente manifest e
link OTA Apple, così l'utente finale installa da Safari senza usare un PC.

Su iOS 27 è supportato anche il percorso gratuito on-device: configurando
`SKINBRIDGE_SIDELOAD_IPA_URL`, la PWA guida prima all'installer ufficiale di
SideStore e poi apre l'IPA con `sidestore://install`. La firma avviene sul
telefono; Wallet Skins non riceve le credenziali Apple.

## Struttura

- `wallet-web`: PWA mobile-first con onboarding, demo, apply/restore e callback.
- `wallet-api`: API senza dipendenze, archivio job in memoria, firma Ed25519,
  TTL massimo 5 minuti (default 120 secondi), token separato per il risultato.
- `SkinBridge-iOS`: helper SwiftUI, deep link, verifica crittografica,
  compatibility check, backup protetto e due executor.
- `docs`: protocollo, stato reale/mock e piano test iPhone.

## Sicurezza e dati

`cardRef` è un riferimento tecnico opaco al pass, non un PAN. L'API rifiuta
ricorsivamente campi chiamati PAN, numero carta, CVV/CVC, token di pagamento o
track data. Non esiste analytics. Il POC conserva i job solo in memoria; il
backup dell'helper è locale con file protection.

## Core AirCard-iOS

Il POC non committa il binario upstream. Per preparare il confine di integrazione:

```sh
chmod +x SkinBridge-iOS/scripts/import-aircard-core.sh
SkinBridge-iOS/scripts/import-aircard-core.sh /path/to/AirCard-iOS
cd SkinBridge-iOS
xcodegen generate --spec project.real.yml
```

Il pacchetto include già framework, pairing e rete con la licenza MIT upstream.
L'executor reale implementa rilevamento carta, backup locale dell'artwork,
generazione asset, scrittura Airlift, invalidazione cache e ripristino. La nuova
primitive di lettura conserva i byte nel sandbox e riscrive immediatamente la
sorgente prima che apply possa procedere; deve essere validata su iPhone reale.

## Limiti intenzionali

- L'API è in-memory e single-process.
- Il custom scheme dimostra il POC; una release dovrebbe aggiungere Universal
  Links e associazione dominio.
- Il mock scarica l'immagine ma non modifica Wallet; il build `project.real.yml`
  usa invece AirliftFFI.
- L'integrazione Airlift è privata/non supportata da Apple e può rompersi con
  qualunque release iOS. Non è una base App Store garantita.
- Su iOS 27, SideInstaller + SideStore consentono anche installazione, pairing e
  rinnovo dal solo iPhone. La disponibilità del certificato pubblico iniziale e
  le possibili revoche dipendono però da servizi esterni e non possono essere
  garantite dal nostro server.

## Licenze

Questa codebase è MIT (`LICENSE`). Le attribuzioni e il testo MIT di
AirCard-iOS sono in `THIRD_PARTY_NOTICES.md` e vengono copiati accanto al
framework importato.
