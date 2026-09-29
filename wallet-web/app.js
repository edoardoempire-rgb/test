const $ = selector => document.querySelector(selector);
const screens = [...document.querySelectorAll(".screen")];

const state = {
  config: {
    helperInstallUrl: null,
    helperInstallMode: null,
    signerSetupUrl: null,
    webDemoEnabled: true,
    executorMode: "mock",
    serverBridgeEnabled: false
  },
  mode: localStorage.getItem("walletSkinsMode") || "demo",
  helperReady: localStorage.getItem("skinBridgeReady") === "true",
  setupReady: localStorage.getItem("skinBridgeSetupReady") === "true",
  cardRef: localStorage.getItem("skinBridgeCardRef") || "",
  selectedSkin: "aurora"
};
let bridgePoll = null;

function show(name) {
  screens.forEach(screen => screen.classList.toggle("active", screen.dataset.screen === name));
  scrollTo({ top: 0, behavior: "smooth" });
}

function setMode(mode) {
  state.mode = mode;
  localStorage.setItem("walletSkinsMode", mode);
  $("#modeBadge").textContent = mode === "demo" ? "DEMO SICURA" : "SKINBRIDGE";
  $("#studioMode").textContent = mode === "demo" ? "Demo" : "Helper";
  $("#cardFieldLabel").textContent = mode === "demo" ? "Nome della carta demo" : "Carta rilevata";
  $("#cardFieldHelp").textContent = mode === "demo"
    ? "È solo un'etichetta per la demo. Non inserire il numero della carta."
    : "Riferimento opaco ricevuto da SkinBridge; non contiene il numero della carta.";
  $("#cardRef").readOnly = mode !== "demo";
  if (mode !== "demo") $("#cardRef").value = state.cardRef || "Nessuna carta rilevata";
  else if (!$("#cardRef").readOnly && $("#cardRef").value === "Nessuna carta rilevata") $("#cardRef").value = "La mia carta";
}

function isIOS() {
  return /iPhone|iPad|iPod/.test(navigator.userAgent)
    || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
}

function callbackUrl(params) {
  const url = new URL(location.origin + "/");
  Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));
  return url.href;
}

async function loadConfig() {
  try {
    const response = await fetch("/v1/config");
    if (response.ok) state.config = await response.json();
  } catch {
    notice("#onboardingNotice", "Il server non risponde. Controlla la connessione e riprova.", "error");
  }
  $("#startDemo").hidden = !state.config.webDemoEnabled;
  $("#startNative").textContent = state.config.serverBridgeEnabled ? "Collega questo iPhone" : "Configura iPhone";
  renderOnboarding();
  if (state.config.serverBridgeEnabled && bridgeSession()) {
    clearInterval(bridgePoll);
    bridgePoll = setInterval(refreshBridge, 1500);
    refreshBridge();
  }
}

function consumeCallback() {
  const params = new URLSearchParams(location.search);
  if (params.get("bridge") === "ready") {
    state.helperReady = true;
    localStorage.setItem("skinBridgeReady", "true");
    setMode("native");
    show("onboarding");
  }
  if (params.get("setup") === "ready") {
    state.helperReady = true;
    state.setupReady = true;
    localStorage.setItem("skinBridgeReady", "true");
    localStorage.setItem("skinBridgeSetupReady", "true");
    setMode("native");
    show("onboarding");
  }
  if (params.get("card")) {
    state.helperReady = true;
    state.setupReady = true;
    state.cardRef = params.get("card");
    localStorage.setItem("skinBridgeReady", "true");
    localStorage.setItem("skinBridgeSetupReady", "true");
    localStorage.setItem("skinBridgeCardRef", state.cardRef);
    setMode("native");
    show("studio");
    notice("#studioStatus", "Configurazione completata. Il tuo iPhone è pronto.", "info");
  }
  if (params.get("studio") === "1") {
    setMode(state.mode);
    show("studio");
  }
  if (["bridge", "setup", "card", "studio", "onboarding"].some(key => params.has(key))) history.replaceState({}, "", "/");
}

function step(element, status, detail) {
  element.classList.remove("ok", "warn", "locked");
  element.classList.add(status);
  element.querySelector(".step-state").textContent = status === "ok" ? "✓" : status === "warn" ? "!" : "";
  if (detail) element.querySelector("small").textContent = detail;
}

function renderOnboarding() {
  if (state.config.serverBridgeEnabled) {
    $("#directPending").hidden = true;
    $("#onboardingFlow").hidden = true;
    $("#serverBridgeFlow").hidden = false;
    return;
  }
  $("#serverBridgeFlow").hidden = true;
  const sideStore = state.config.helperInstallMode === "sidestore";
  const technicalMode = new URLSearchParams(location.search).get("technical") === "1";
  const directPending = sideStore && !technicalMode;
  $("#directPending").hidden = !directPending;
  $("#onboardingFlow").hidden = directPending;
  if (directPending) return;

  const deviceOK = isIOS() && (isSecureContext || location.hostname === "localhost");
  step(
    $("#deviceStep"),
    deviceOK ? "ok" : "warn",
    !isIOS()
      ? "Apri questa pagina con Safari su iPhone."
      : !isSecureContext && location.hostname !== "localhost"
        ? "Serve un indirizzo HTTPS per usare il flusso sul telefono."
        : "iPhone e connessione sicura rilevati."
  );

  const installConfigured = Boolean(state.config.helperInstallUrl);
  const installText = state.config.helperInstallMode === "ota"
    ? "Tocca Installa: iOS scaricherà la build firmata direttamente."
    : sideStore
      ? "Su iOS 27 prepara SideStore sul telefono, poi installa SkinBridge."
      : "Installa l'helper, poi torna qui.";
  step(
    $("#installStep"),
    state.helperReady ? "ok" : installConfigured ? "warn" : "locked",
    state.helperReady
      ? "SkinBridge ha risposto correttamente."
      : installConfigured
        ? installText
        : "Manca ancora una build SkinBridge installabile per questo iPhone."
  );
  $("#installSigner").hidden = !sideStore || state.helperReady;
  $("#sideStoreGuide").hidden = !sideStore || state.helperReady;
  $("#installHelper").textContent = sideStore ? "2. Installa SkinBridge" : "Installa SkinBridge";
  $("#installHelper").disabled = state.helperReady || !installConfigured;

  const automaticReady = state.helperReady && state.setupReady && Boolean(state.cardRef);
  step(
    $("#automationStep"),
    automaticReady ? "ok" : deviceOK && installConfigured ? "warn" : "locked",
    automaticReady
      ? "SkinBridge configurata e carta collegata con riferimento opaco."
      : "Un'unica procedura per controllo, VPN, pairing e carta. Non leggerà numero, CVV o token."
  );
  $("#startAutomation").disabled = !deviceOK || !installConfigured || automaticReady;
  $("#progressBar").style.width = `${[deviceOK, state.helperReady, automaticReady].filter(Boolean).length * (100 / 3)}%`;
}

function bridgeSession() {
  try { return JSON.parse(sessionStorage.getItem("walletBridgeSession") || "null"); } catch { return null; }
}

async function refreshBridge() {
  const session = bridgeSession();
  if (!session) return;
  try {
    const response = await fetch(`/v1/server-bridge/sessions/${encodeURIComponent(session.id)}?token=${encodeURIComponent(session.token)}`);
    const status = await response.json();
    if (!response.ok) throw new Error(status.error || "La sessione è scaduta.");
    if (["profile_ready", "pin_ready", "paired", "checking", "ready"].includes(status.state)) {
      $("#bridgeProgress").style.width = status.state === "ready" ? "100%" : ["paired", "checking"].includes(status.state) ? "90%" : status.state === "pin_ready" ? "75%" : "50%";
      $("#checkPairing").disabled = false;
    }
    if (status.state === "pin_ready") {
      $("#pairPin").hidden = false;
      $("#pairPinValue").textContent = status.pin;
      $("#bridgePairText").textContent = "Inserisci questo codice nella richiesta mostrata da iPhone.";
    }
    if (["paired", "checking"].includes(status.state)) {
      $("#pairPin").hidden = true;
      $("#bridgePairText").textContent = `${status.deviceName || "iPhone"} abbinato. Controllo la compatibilità…`;
    }
    if (status.state === "ready") {
      clearInterval(bridgePoll);
      $("#pairPin").hidden = true;
      $("#bridgePairText").textContent = `${status.deviceName || "iPhone"} pronto e compatibile.`;
      $("#bridgePairText").classList.add("bridge-ok");
      notice("#bridgeNotice", "Collegamento verificato. Wallet Skins può comunicare con questo iPhone senza installare app.", "info");
      $("#checkPairing").textContent = "iPhone pronto ✓";
      $("#checkPairing").disabled = true;
    } else if (status.state === "error" || status.state === "expired") {
      clearInterval(bridgePoll);
      throw new Error(status.error || "La sessione è scaduta. Tocca di nuovo Collega iPhone.");
    }
  } catch (error) {
    clearInterval(bridgePoll);
    notice("#bridgeNotice", error.message, "error");
  }
}

async function connectPhone() {
  if (!isIOS()) {
    notice("#bridgeNotice", "Apri questa pagina con Safari sul tuo iPhone.", "warn");
    return;
  }
  $("#connectPhone").disabled = true;
  $("#connectPhone").textContent = "Preparo la connessione…";
  try {
    const response = await fetch("/v1/server-bridge/sessions", { method: "POST" });
    const session = await response.json();
    if (!response.ok) throw new Error(session.error || "Non riesco a preparare la connessione.");
    sessionStorage.setItem("walletBridgeSession", JSON.stringify({ id: session.id, token: session.token }));
    $("#bridgeProgress").style.width = "35%";
    $("#bridgeInstallText").textContent = "Profilo pronto. Accetta il download, poi apri Impostazioni > Profilo scaricato e tocca Installa.";
    $("#connectPhone").textContent = "Profilo scaricato";
    $("#checkPairing").disabled = false;
    clearInterval(bridgePoll);
    bridgePoll = setInterval(refreshBridge, 1500);
    location.href = session.profileUrl;
  } catch (error) {
    $("#connectPhone").disabled = false;
    $("#connectPhone").textContent = "Collega iPhone →";
    notice("#bridgeNotice", error.message, "error");
  }
}

function notice(selector, text, kind = "info") {
  const node = $(selector);
  node.hidden = false;
  node.className = `notice ${kind}`;
  node.textContent = text;
}

function launchScheme(url, fallbackMessage) {
  let backgrounded = false;
  const change = () => { if (document.hidden) backgrounded = true; };
  document.addEventListener("visibilitychange", change, { once: true });
  location.href = url;
  setTimeout(() => {
    if (!backgrounded) notice("#onboardingNotice", fallbackMessage, "warn");
  }, 1800);
}

async function createJob(action) {
  const raw = state.mode === "demo" ? $("#cardRef").value : state.cardRef;
  const cardRef = raw.trim().replaceAll(/[^A-Za-z0-9._+=-]/g, "-").slice(0, 128);
  if (cardRef.length < 3) {
    throw new Error(state.mode === "demo"
      ? "Dai alla carta demo un nome di almeno tre caratteri."
      : "Rileva prima una carta con SkinBridge.");
  }
  const payload = { action, cardRef };
  if (action === "apply") payload.assetUrl = `/skins/${state.selectedSkin}.png`;
  const response = await fetch("/v1/jobs", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  const job = await response.json();
  if (!response.ok) throw new Error(job.error || "Non riesco a creare il job.");
  sessionStorage.setItem("walletSkinsJob", job.envelope.payload.jobId);
  return job;
}

async function run(action) {
  show("working");
  ["#workSigned", "#workExecuted", "#workCallback"].forEach(selector => $(selector).classList.remove("done"));
  $("#workingTitle").textContent = action === "apply" ? "Preparo la tua skin…" : "Preparo il ripristino…";
  try {
    const job = await createJob(action);
    $("#workSigned").classList.add("done");
    if (state.mode === "demo") {
      $("#workingDetail").textContent = "La demo simula SkinBridge senza modificare Wallet.";
      await new Promise(resolve => setTimeout(resolve, 600));
      const response = await fetch(`/v1/jobs/${job.envelope.payload.jobId}/demo-execute`, { method: "POST" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      $("#workExecuted").classList.add("done");
      await new Promise(resolve => setTimeout(resolve, 450));
      $("#workCallback").classList.add("done");
      location.href = `/callback.html?job=${encodeURIComponent(job.envelope.payload.jobId)}&mode=demo`;
    } else {
      $("#workingDetail").textContent = "Apro SkinBridge. Segui le indicazioni che appariranno sul telefono.";
      location.href = job.deepLink;
    }
  } catch (error) {
    show("studio");
    notice("#studioStatus", error.message, "error");
  }
}

document.querySelectorAll("[data-go]").forEach(button => button.addEventListener("click", () => show(button.dataset.go)));
$("#startDemo").addEventListener("click", () => { setMode("demo"); show("studio"); });
$("#startNative").addEventListener("click", () => { setMode("native"); renderOnboarding(); show("onboarding"); });
$("#connectPhone").addEventListener("click", connectPhone);
$("#checkPairing").addEventListener("click", refreshBridge);
$("#retryDirect").addEventListener("click", loadConfig);
$("#installSigner").addEventListener("click", () => {
  if (state.config.signerSetupUrl) location.href = state.config.signerSetupUrl;
});
$("#installHelper").addEventListener("click", () => {
  if (state.config.helperInstallMode === "sidestore") {
    launchScheme(state.config.helperInstallUrl, "SideStore non si è aperto. Completa prima il pulsante 1 e autorizza SideStore nelle Impostazioni.");
  } else {
    location.href = state.config.helperInstallUrl;
  }
});
$("#startAutomation").addEventListener("click", () => launchScheme(
  `skinbridge://onboard?callback=${encodeURIComponent(callbackUrl({ onboarding: "complete" }))}`,
  "SkinBridge non si è aperto. Installalo dal passaggio precedente, quindi tocca di nuovo questo pulsante."
));

document.querySelectorAll(".swatch").forEach(button => button.addEventListener("click", () => {
  state.selectedSkin = button.dataset.skin;
  document.querySelectorAll(".swatch").forEach(item => item.classList.toggle("selected", item === button));
  $("#skinPreview").className = `skin-preview skin-${state.selectedSkin}`;
}));
$("#applySkin").addEventListener("click", () => run("apply"));
$("#restoreSkin").addEventListener("click", () => run("restore"));

const dialog = $("#privacyDialog");
$("#privacyButton").addEventListener("click", () => dialog.showModal());
$(".dialog-close").addEventListener("click", () => dialog.close());
$(".dialog-ok").addEventListener("click", () => dialog.close());
window.addEventListener("pageshow", renderOnboarding);

await loadConfig();
consumeCallback();
renderOnboarding();
if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js");
