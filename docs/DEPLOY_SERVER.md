# Pubblicazione sul proprio server

La demo web guidata si prova interamente da iPhone e non richiede SkinBridge.
Per Safari servono un dominio pubblico e HTTPS valido.

## Requisiti del server

- server Linux con indirizzo pubblico;
- Docker con Compose;
- un dominio il cui record DNS punta al server;
- porte 80 e 443 aperte.

## Configurazione

1. Copiare il progetto sul server.
2. Copiare `.env.example` in `.env`.
3. Impostare almeno:

```dotenv
DOMAIN=wallet.example.com
PUBLIC_BASE_URL=https://wallet.example.com
WEB_CALLBACK_URL=https://wallet.example.com/callback.html
ALLOW_WEB_DEMO=true
EXECUTOR_MODE=mock
```

Lasciare `HELPER_INSTALL_URL` vuoto finché non esiste una build TestFlight o un
link IPA installabile. La demo web continuerà a funzionare.

Per una build ad hoc/enterprise firmata, copiare `SkinBridge.ipa` nella cartella
`downloads/` e impostare invece:

```dotenv
SKINBRIDGE_IPA_URL=https://wallet.example.com/downloads/SkinBridge.ipa
SKINBRIDGE_BUNDLE_ID=com.walletskins.skinbridge
SKINBRIDGE_VERSION=0.1.0
```

Il manifest Apple e il link d'installazione vengono generati dal server.

Per il percorso gratuito senza PC su iOS 27, pubblicare l'IPA non firmata in
una release GitHub pubblica o in `downloads/` e impostare:

```dotenv
SKINBRIDGE_SIDELOAD_IPA_URL=https://github.com/OWNER/REPO/releases/download/skinbridge-latest/SkinBridge-unsigned.ipa
SIDESTORE_SETUP_URL=https://sideinstaller.net/
```

La PWA mostrerà la guida SideInstaller/SideStore e aprirà l'IPA con il protocollo
ufficiale `sidestore://install?url=...`.

4. Avviare:

```sh
docker compose up -d --build
```

Caddy richiede automaticamente il certificato HTTPS. Aprire quindi
`https://wallet.example.com` con Safari su iPhone e scegliere **Prova la demo
guidata**.

## Risultato atteso

La persona sceglie una skin, le assegna un nome locale, preme Applica e vede:

1. creazione del job firmato;
2. esecuzione demo;
3. callback e risultato;
4. backup simulato disponibile per il successivo Restore.

La pagina dichiara sempre che Wallet non è stato modificato. Il percorso
**Configura SkinBridge** resta bloccato finché non viene configurato uno fra
`HELPER_INSTALL_URL`, `SKINBRIDGE_IPA_URL` e `SKINBRIDGE_SIDELOAD_IPA_URL`.

## Controllo rapido

```sh
curl https://wallet.example.com/health
```

Deve restituire `{"ok":true,...}`.

## Prima di utenti esterni

- sostituire la chiave Ed25519 di sviluppo;
- ricompilare SkinBridge con la nuova chiave pubblica;
- disattivare la demo con `ALLOW_WEB_DEMO=false` quando il core reale sarà validato;
- aggiungere persistenza, rate limiting e consumo atomico dei job;
- non pubblicizzare una modifica reale di Wallet finché backup e restore reali
  non superano i test su device.
