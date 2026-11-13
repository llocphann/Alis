"use strict";

const BRIDGE_BASE = "http://127.0.0.1:43821";
const THEME_URL = `${BRIDGE_BASE}/theme`;
const EVENTS_URL = `${BRIDGE_BASE}/events`;

let eventSource = null;
let reconnectTimer = null;
let lastSignature = "";

async function applyPayload(payload) {
  if (!payload || typeof payload !== "object") {
    return;
  }
  if (payload.enabled === false) {
    if (lastSignature !== "__disabled__") {
      lastSignature = "__disabled__";
      try {
        await browser.theme.reset();
      } catch (err) {
        console.warn("[Alis Live Theme] reset failed:", err);
      }
    }
    return;
  }

  const geckoTheme = payload.gecko_theme;
  if (!geckoTheme || typeof geckoTheme !== "object" || !geckoTheme.colors) {
    return;
  }

  const sig = JSON.stringify(geckoTheme);
  if (sig === lastSignature) {
    return;
  }
  lastSignature = sig;

  try {
    await browser.theme.update(geckoTheme);
  } catch (err) {
    console.warn("[Alis Live Theme] update failed:", err);
  }
}

async function fetchInitialTheme() {
  try {
    const resp = await fetch(THEME_URL, { cache: "no-store" });
    if (resp.ok) {
      const data = await resp.json();
      await applyPayload(data);
    }
  } catch (_) {
    // Bridge may not be running yet; SSE reconnect loop will pick it up.
  }
}

function scheduleReconnect(delayMs = 2500) {
  if (reconnectTimer !== null) {
    return;
  }
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectStream();
  }, delayMs);
}

function connectStream() {
  if (eventSource) {
    try {
      eventSource.close();
    } catch (_) {}
    eventSource = null;
  }

  try {
    const es = new EventSource(EVENTS_URL);
    eventSource = es;

    es.onmessage = (event) => {
      if (!event || !event.data) {
        return;
      }
      try {
        const data = JSON.parse(event.data);
        applyPayload(data);
      } catch (err) {
        console.warn("[Alis Live Theme] bad SSE payload:", err);
      }
    };

    es.onerror = () => {
      try {
        es.close();
      } catch (_) {}
      if (eventSource === es) {
        eventSource = null;
      }
      scheduleReconnect(2500);
    };
  } catch (_) {
    scheduleReconnect(3000);
  }
}

browser.runtime.onInstalled.addListener(() => {
  lastSignature = "";
  fetchInitialTheme();
});

browser.runtime.onStartup.addListener(() => {
  lastSignature = "";
  fetchInitialTheme();
});

fetchInitialTheme();
connectStream();
