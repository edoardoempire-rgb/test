# Build e installazione senza usare il PC dell'utente

Il repository include `.github/workflows/build-skinbridge-ipa.yml`. Ogni modifica
alla cartella iOS avvia una build su un runner macOS e produce l'artefatto
`SkinBridge-unsigned-ipa`.

## Preparazione una tantum del progetto

1. Pubblicare questo progetto in un repository GitHub pubblico. L'IPA della
   release deve essere scaricabile dall'iPhone senza un token GitHub.
2. Aprire Actions → Build SkinBridge IPA → Run workflow.
3. Il workflow crea/aggiorna automaticamente la release `skinbridge-latest` e
   il file `SkinBridge-unsigned.ipa`.
4. Inserire l'URL pubblico dell'asset in `SKINBRIDGE_SIDELOAD_IPA_URL` sul
   server. In alternativa firmare l'IPA e usare il percorso OTA descritto sotto.

## Esperienza dell'utente finale

L'utente opera solo dall'iPhone:

1. apre il sito;
2. tocca **Configura SkinBridge**;
3. segue il link di installazione;
4. torna al sito e verifica l'helper;
5. SkinBridge guida LocalDevVPN e pairing on-device;
6. apre Wallet e seleziona la carta seguendo le istruzioni;
7. sceglie la skin nella PWA e preme Applica.

L'IPA non firmata non può essere installata direttamente da Safari. Deve essere
firmata da TestFlight/ad hoc oppure aperta con un sideload manager compatibile.
Questa è una regola della piattaforma iOS, non una limitazione della PWA.

## Installazione OTA automatica dal sito

Per l'esperienza senza PC dell'utente finale, firmare SkinBridge con un profilo
ad hoc/enterprise valido per il dispositivo e copiare il file sul server in:

```text
/opt/wallet-skins/downloads/SkinBridge.ipa
```

Poi impostare nel `.env`:

```dotenv
SKINBRIDGE_IPA_URL=https://wallet.example.com/downloads/SkinBridge.ipa
SKINBRIDGE_BUNDLE_ID=com.walletskins.skinbridge
SKINBRIDGE_VERSION=0.1.0
```

Il backend espone automaticamente `/install/manifest.plist` e restituisce alla
PWA un link `itms-services://`. Da quel momento **Apri installazione** avvia il
download firmato con un solo tocco da Safari. Se si usa TestFlight, lasciare
`SKINBRIDGE_IPA_URL` vuoto e inserire il link pubblico in `HELPER_INSTALL_URL`.

La firma non può essere generata dal solo codice sorgente: servono un
certificato Apple e un provisioning profile che includa l'iPhone, oppure una
distribuzione Apple equivalente.

## Percorso gratuito interamente da iPhone (iOS 27)

Il workflow GitHub manuale pubblica anche una release stabile
`skinbridge-latest` con `SkinBridge-unsigned.ipa`. Configurare il server con:

```dotenv
SKINBRIDGE_SIDELOAD_IPA_URL=https://github.com/OWNER/REPO/releases/download/skinbridge-latest/SkinBridge-unsigned.ipa
SIDESTORE_SETUP_URL=https://sideinstaller.net/
```

La PWA mostra quindi due pulsanti guidati:

1. apre esclusivamente il sito ufficiale SideInstaller, che prepara SideStore
   direttamente su iOS 27;
2. apre `sidestore://install?url=...`, così SideStore scarica, firma localmente
   con l'Apple Account dell'utente e installa SkinBridge.

Con un account Apple gratuito le app hanno normalmente una durata di sette
giorni. SideStore le rinnova sul dispositivo; LocalDevVPN deve essere attiva
durante installazione, aggiornamento o refresh.

Le credenziali Apple non passano mai attraverso Wallet Skins. SideInstaller e
SideStore restano componenti esterni: disponibilità del certificato iniziale,
revoche e limiti della firma gratuita non sono controllabili dal nostro server.

## Stato reale

- Pairing on-device: implementato tramite il controller MIT upstream.
- Rilevamento carta: implementato tramite syslog Airlift.
- Apply: implementato con asset @2x/@3x/PDF e invalidazione cache.
- Callback Safari: implementata.
- Build IPA cloud: configurata.
- Backup originale: implementato tramite un'estensione della FFI che esporta
  tutti gli artwork noti e ripristina immediatamente la sorgente durante la
  lettura.
- Restore reale: riscrive i file originali, byte per byte, dal backup locale ed
  è bloccato se il backup manca.

La lettura di backup, la riscrittura e l'effettivo refresh di Wallet vanno
ancora validati su un iPhone fisico. Finché quel test non passa, non descrivere
il core reale come garantito al 100%.
