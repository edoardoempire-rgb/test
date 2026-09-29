# Installazione diretta di SkinBridge

Questo percorso serve a mostrare all'utente un solo pulsante di installazione, senza SideStore, SideInstaller o un computer sul dispositivo finale.

## Requisiti

L'IPA deve essere firmata con asset Apple validi e coerenti con `com.walletskins.skinbridge`:

- certificato di distribuzione esportato come `.p12`;
- password del `.p12`;
- profilo `.mobileprovision` Ad Hoc che includa gli iPhone autorizzati.

La distribuzione Ad Hoc è destinata a test su dispositivi registrati e non richiede la pubblicazione sull'App Store. Non è una distribuzione pubblica illimitata. I profili Enterprise sono ammessi da Apple soltanto per applicazioni interne ai dipendenti dell'organizzazione titolare.

## Segreti GitHub

Inserire in **Settings → Secrets and variables → Actions**:

- `IOS_CERTIFICATE_P12_BASE64`: contenuto Base64 del `.p12`;
- `IOS_CERTIFICATE_PASSWORD`: password del `.p12`;
- `IOS_MOBILEPROVISION_BASE64`: contenuto Base64 del `.mobileprovision` dell'app;
- `IOS_TUNNEL_MOBILEPROVISION_BASE64`: contenuto Base64 del profilo della
  Network Extension `com.walletskins.skinbridge.tunnel`.

Non caricare mai questi file nel repository e non incollarli in chat. Dopo l'inserimento, eseguire **Build SkinBridge IPA**. La pipeline:

1. compila il core reale Airlift;
2. firma e verifica `SkinBridge-signed.ipa`;
3. pubblica l'IPA nella release stabile;
4. avvia automaticamente il deploy del VPS;
5. configura la PWA in modalità OTA diretta quando trova l'IPA firmata.

Senza questi segreti la pipeline pubblica soltanto l'IPA non firmata di test.
Il profilo del tunnel deve autorizzare `packet-tunnel-provider`; una firma che
non contiene questo entitlement non può produrre la variante tutto-in-uno.

## Esperienza dell'utente

Con la firma disponibile, l'utente finale:

1. tocca **Installa SkinBridge** sul sito;
2. accetta le schermate di sicurezza mostrate da iOS;
3. abilita Modalità sviluppatore se richiesta;
4. apre SkinBridge e segue la configurazione guidata.

Non deve installare SideStore, SideInstaller, LocalDevVPN o usare un PC. Al
primo avvio iOS mostra l'autorizzazione VPN del tunnel locale incorporato.
L'installazione va comunque verificata su un iPhone reale prima di offrirla ad
altri tester.
