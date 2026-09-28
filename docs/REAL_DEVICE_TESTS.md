# Stato e test su iPhone reale

## Funziona ora

- Creazione e firma Ed25519 dei job con scadenza breve.
- Deep link `skinbridge://` e ritorno a Safari.
- Verifica locale di firma, scadenza e schema payload.
- Apply/restore mock con backup locale protetto.
- Pubblicazione e visualizzazione dell'esito.
- Rifiuto API dei più comuni campi contenenti credenziali di pagamento.

## Mockato nel build demo

- Rilevamento carta e lettura degli artwork originali.
- Scrittura AirTraffic/Passbook e invalidazione cache.
- Verifica effettiva di LocalDevVPN.

Il build reale usa `al_syslog_stream_start` per il rilevamento,
`al_exploit_read_file` per acquisire e ripristinare immediatamente l'artwork
originale, e `al_exploit_write_dir` per apply/restore e invalidazione cache. La
primitive di lettura è un'estensione locale del core MIT upstream e non è ancora
stata eseguita su un iPhone fisico: il primo test deve verificare hash e presenza
della sorgente prima e dopo il backup.

## Checklist iPhone — round-trip mock

1. Servire API/PWA su HTTPS raggiungibile dall'iPhone e configurare entrambi gli
   URL pubblici.
2. Ruotare la chiave POC e aggiornare la chiave pubblica nell'app.
3. Installare il build mock di SkinBridge e aprirlo una volta.
4. In Safari creare un job apply; confermare apertura app, esito mock e ritorno.
5. Ripetere con restore e confermare che il backup locale venga trovato.
6. Provare un job dopo 120 secondi, una firma alterata e un result token errato.
7. Spegnere rete durante download e verificare `failed` + callback.

## Checklist iPhone — core reale (gated)

1. Compilare su iPhone arm64 con il framework importato e relative attribuzioni.
2. Verificare la versione iOS contro la matrice upstream (attualmente dichiarata
   iOS 27+) e annotare modello/build esatti.
3. Installare/attivare LocalDevVPN e controllare il percorso loopback.
4. Eseguire il pairing on-device da Developer Mode; riavviare e verificare che
   persista senza Mac.
5. Testare la read primitive già implementata, confrontando hash e dimensioni
   di ogni asset originale prima di sbloccare apply.
6. Su una carta di test, generare gli asset 1536×969 e 1024×646, scrivere nella
   `.pkpass`, invalidare `FrontFace`, `Preview`, `PlaceHolder` nelle cache e
   forzare la riapertura di Wallet.
7. Eseguire restore dal backup, verificare byte/hash e ripetere dopo reboot.
8. Ripetere senza computer collegato. Questo è il vero criterio zero-PC.

Non usare carte critiche o un device principale finché backup/restore reale non
ha superato test ripetibili e indipendenti.
