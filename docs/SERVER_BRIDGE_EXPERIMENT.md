# Esperimento server bridge (zero app aggiuntive)

Questa è una seconda architettura sperimentale. Sposta pairing, tunnel RSD e
AirLift sul VPS, invece di eseguirli dentro SkinBridge.

## Obiettivo del test

Flusso previsto su iPhone:

1. Safari installa un profilo IKEv2 del servizio e l'utente accetta la VPN.
2. In **Impostazioni > Privacy e sicurezza > Modalità sviluppatore**, l'utente
   seleziona **Wallet Skins Gateway** e inserisce il PIN mostrato dal sito.
3. Il sito controlla la connessione e può eseguire apply/restore dal VPS.

Non vengono installate SideStore, LocalDevVPN o SkinBridge. Il profilo VPN è
rimovibile dalle Impostazioni.

## Componenti già pronti

- `airlift-gateway pair`: avvia sul server l'host RPPairing e produce eventi
  JSON per service ID, record DNS-SD, PIN e risultato.
- `airlift-gateway probe`: verifica pairing e tunnel verso l'IP privato
  dell'iPhone senza modificare Wallet.
- `AIRLIFT_DEVICE_ENDPOINT`: permette al core AirLift di usare un endpoint VPN
  remoto invece dei soli indirizzi loopback di LocalDevVPN.
- La pipeline `Build AirLift Gateway` compila e testa il binario Linux.

## Verifica ancora necessaria

Il passaggio non dimostrato è la discovery del pairing host dalla schermata
Developer Mode attraverso il VPN integrato. Il POC userà DNS-SD wide-area nel
dominio di ricerca consegnato dal profilo IKEv2. Solo una prova su iPhone reale
può confermare se la schermata Apple consulta i domini DNS-SD configurati o
limita la ricerca a Bonjour `.local`.

Se il nome appare e il pairing termina, questa architettura elimina del tutto
il problema della firma e dell'installazione dell'IPA. Se Apple limita quella
schermata a `.local`, non è possibile completare il bootstrap da un VPS senza
un'app, un dispositivo già abbinato o un host nella stessa LAN.

## Sicurezza

Il record RPPairing consente accesso privilegiato ai servizi sviluppatore del
telefono. In un servizio reale deve essere cifrato con una chiave per utente,
mai registrato nei log e cancellato quando l'utente rimuove il dispositivo.
Apply e restore devono restare operazioni esplicitamente confermate e
verificabili; PAN, CVV e token di pagamento non sono necessari e non devono
essere raccolti.
