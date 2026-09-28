# Protocollo POC

1. La PWA invia `POST /v1/jobs` con `action`, `cardRef` opaco e, per apply,
   `assetUrl`.
2. L'API crea payload versione 1, nonce casuale, `issuedAt`, `expiresAt`, URL di
   risultato/callback e token casuale per pubblicare il risultato.
3. L'API firma la serializzazione JSON canonica (chiavi ordinate) con Ed25519 e
   restituisce `skinbridge://job?api=…&job=…`.
4. SkinBridge scarica l'envelope, controlla key ID, firma, versione, azione,
   clock skew e TTL massimo di 300 secondi.
5. Il compatibility check decide se l'executor può procedere. L'executor reale
   deve confermare iOS supportato, pairing, tunnel e capacità di backup.
6. L'executor pubblica `succeeded`, `failed` o `incompatible` usando il token del
   risultato. Poi apre `callbackUrl?job=…` in Safari.
7. La callback legge lo stato dall'API. Non si fida di un esito inserito nel
   deep link.

Il token di risultato non sostituisce la firma: serve solo a impedire update
casuali. Il POC lo consuma una sola volta nel processo corrente. Per produzione
andrebbero aggiunti consumo atomico persistente, rate limit, binding al device
e rotazione chiavi.

## Onboarding helper

- `skinbridge://ping?callback=…` apre l'helper e ritorna subito alla PWA; serve
  per verificare l'installazione senza dedurla dal solo user agent.
- `skinbridge://setup?callback=…` apre la checklist nativa per VPN, pairing e
  compatibilità; la callback viene aperta solo quando il build in uso è pronto.
- Se l'helper non si apre, la PWA presenta il metodo configurato (TestFlight,
  OTA firmata o SideInstaller/SideStore) e una spiegazione concreta.

## Demo web

Con `ALLOW_WEB_DEMO=true`, `POST /v1/jobs/:id/demo-execute` consuma un job e
simula apply/restore. Restore è consentito solo dopo un apply per lo stesso
`cardRef`. Questa rotta non apre SkinBridge e non modifica Wallet; esiste solo
per provare da telefono l'esperienza pubblicata sul server.
