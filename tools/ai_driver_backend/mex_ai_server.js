"use strict";

// MEX AI Driver - NDJSON/TCP <-> Ollama bridge. Node.js >= 18 (20+ recommended).
// This process does NOT control a train or bypass the in-game safety controller.
const net = require("node:net");
const fs = require("node:fs");
const path = require("node:path");

const config = Object.freeze({
  host: process.env.MEX_AI_HOST || "127.0.0.1",
  port: integerEnv("MEX_AI_PORT", 3002, 1, 65535),
  model: process.env.OLLAMA_MODEL || "qwen3:8b",
  ollamaUrl: (process.env.OLLAMA_URL || "http://127.0.0.1:11434").replace(/\/$/, ""),
  timeoutMs: integerEnv("MEX_AI_TIMEOUT_MS", 20000, 1000, 120000),
  maxActive: integerEnv("MEX_AI_MAX_ACTIVE", 2, 1, 16),
  maxBytes: 32768,
  rulesFile: path.join(__dirname, "driver_guide.md")
});

function integerEnv(key, fallback, min, max) {
  const raw = Number(process.env[key]);
  return process.env[key] && Number.isInteger(raw) && raw >= min && raw <= max ? raw : fallback;
}
function number(value, min, max) {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max ? value : null;
}
function optionalNumber(value, min, max) {
  return value == null ? null : number(value, min, max);
}
function sanitizeText(value, max = 90) {
  return typeof value === "string" ? value.slice(0, max) : "";
}
function clamp(x, lo, hi) { return Math.min(hi, Math.max(lo, x)); }

// Input never authorizes actuator positions. Non-finite and impossible values are rejected.
function normalizeRequest(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw Error("invalid request");
  if (data.v !== 1 || data.type !== "decision") throw Error("unsupported protocol/version");
  if (typeof data.id !== "string" || !/^[a-zA-Z0-9:_-]{1,64}$/.test(data.id)) throw Error("invalid id");
  const t = data.train;
  const r = data.route;
  if (!t || typeof t !== "object" || !r || typeof r !== "object") throw Error("train/route required");
  const speed = number(t.speed_kmh, 0, 160);
  if (speed === null) throw Error("invalid speed_kmh");
  const route = {
    known: r.known === true,
    traction_allowed: typeof r.traction_allowed === "boolean" ? r.traction_allowed : null,
    brake_prepare_active: r.brake_prepare_active === true,
    current_limit_kmh: optionalNumber(r.current_limit_kmh, 0, 120),
    next_sign: null,
    signal: null,
    stop_distance_m: optionalNumber(r.stop_distance_m, 0, 5000)
  };
  if (r.next_sign && typeof r.next_sign === "object") {
    const sign = r.next_sign;
    const kind = sanitizeText(sign.kind, 40);
    const distance = optionalNumber(sign.distance_m, 0, 5000);
    const value = optionalNumber(sign.value_kmh, 0, 120);
    if (["SPEED_LIMIT", "BRAKE_PREPARE", "TRACTION_ALLOWED", "TRACTION_OFF"].includes(kind) && distance !== null && (kind !== "SPEED_LIMIT" || value !== null)) {
      route.next_sign = { kind, distance_m: distance, value_kmh: value };
    }
  }
  if (r.signal && typeof r.signal === "object") {
    const aspect = sanitizeText(r.signal.aspect, 16);
    const distance = optionalNumber(r.signal.distance_m, 0, 5000);
    if (["RED", "YELLOW", "GREEN", "UNKNOWN"].includes(aspect) && distance !== null) {
      route.signal = { aspect, distance_m: distance };
    }
  }
  return {
    v: 1, id: data.id, type: "decision",
    train: {
      id: sanitizeText(t.id, 64),
      class: sanitizeText(t.class, 80),
      speed_kmh: speed,
      ars_limit_kmh: optionalNumber(t.ars_limit_kmh, 0, 120),
      kv_position: optionalNumber(t.kv_position, -3, 3),
      reverser_position: optionalNumber(t.reverser_position, -1, 1),
      doors_closed: typeof t.doors_closed === "boolean" ? t.doors_closed : null,
      driver_present: typeof t.driver_present === "boolean" ? t.driver_present : null
    },
    route
  };
}

// Safety envelope is duplicated in Lua: it is independently re-evaluated every 0.1 s.
function envelope(input) {
  const t = input.train;
  const r = input.route;
  if (!r.known) return { safeSpeed: 0, reason: "route_unknown" };
  const limits = [120];
  if (r.current_limit_kmh !== null) limits.push(r.current_limit_kmh);
  if (t.ars_limit_kmh !== null) limits.push(t.ars_limit_kmh);
  // Unknown ARS is NOT automatically interpreted as unrestricted: a known
  // explicit route limit is required, otherwise no powered movement.
  if (r.current_limit_kmh === null && t.ars_limit_kmh === null) return { safeSpeed: 0, reason: "no_speed_authority" };
  const approachSpeed = (target, distance) => {
    const deceleration = 0.75; // m/s^2 conservative initial simulation setting
    const margin = 15;         // m (further train-specific calibration required)
    const usable = Math.max(0, distance - margin);
    return Math.sqrt((target / 3.6) ** 2 + 2 * deceleration * usable) * 3.6;
  };
  if (r.next_sign && r.next_sign.kind === "SPEED_LIMIT") {
    limits.push(approachSpeed(r.next_sign.value_kmh, r.next_sign.distance_m));
  }
  if (r.signal && ["RED", "UNKNOWN"].includes(r.signal.aspect)) {
    limits.push(approachSpeed(0, r.signal.distance_m));
  }
  if (r.stop_distance_m !== null) limits.push(approachSpeed(0, r.stop_distance_m));
  if (t.doors_closed === false || t.driver_present === true) return {safeSpeed: 0, reason: "interlock"};
  // Traction authority is independent of the numerical speed envelope.
  // Do not reduce speed to zero just because a driver is coasting without power.
  return { safeSpeed: Math.max(0, Math.min(...limits)), reason: "route_envelope" };
}

function parseModelDecision(raw) {
  if (typeof raw !== "string" || raw.length > 4096) throw Error("invalid model reply");
  const data = JSON.parse(raw);
  if (!data || Array.isArray(data) || typeof data !== "object") throw Error("invalid decision");
  if (!["ACCELERATE", "COAST", "BRAKE", "HOLD", "STOP"].includes(data.mode)) throw Error("invalid mode");
  if (number(data.target_speed_kmh, 0, 120) === null) throw Error("invalid target speed");
  return { mode: data.mode, target_speed_kmh: data.target_speed_kmh, reason: sanitizeText(data.reason, 180) };
}

function safeDecision(input, proposed, status = "ok") {
  const { safeSpeed, reason } = envelope(input);
  const speed = input.train.speed_kmh;
  const target = proposed ? Math.min(proposed.target_speed_kmh, safeSpeed) : 0;
  let mode = proposed ? proposed.mode : "BRAKE";
  // Enforce the envelope even when the model hallucinates permission to accelerate.
  if (speed > safeSpeed + 0.5 || speed > target + 2) mode = "BRAKE";
  else if (target < 0.5 && speed > 0.5) mode = "BRAKE";
  else if (target < 0.5 && speed <= 0.5) mode = "HOLD";
  else if (mode === "ACCELERATE" && speed >= target - 1) mode = "COAST";
  if (mode === "STOP" && speed > 0.5) mode = "BRAKE";
  if (input.route.brake_prepare_active && speed > 2) mode = "BRAKE";
  if (input.route.traction_allowed === false && mode === "ACCELERATE") mode = "COAST";
  return {
    v: 1, type: "decision", id: input.id,
    mode, target_speed_kmh: Math.round(target * 10) / 10,
    safe_speed_kmh: Math.round(safeSpeed * 10) / 10,
    reason: proposed ? proposed.reason : reason,
    status,
    // Never include an inferred hardware position: actuators belong to GMod.
  };
}

const decisionSchema = {
  type: "object", additionalProperties: false,
  required: ["mode", "target_speed_kmh", "reason"],
  properties: {
    mode: { type: "string", enum: ["ACCELERATE", "COAST", "BRAKE", "HOLD", "STOP"] },
    target_speed_kmh: { type: "number", minimum: 0, maximum: 120 },
    reason: { type: "string" }
  }
};

let cachedGuide = "";
let guideMtime = -1;
function readGuide(filePath = config.rulesFile) {
  const stat = fs.statSync(filePath);
  if (cachedGuide && guideMtime === stat.mtimeMs) return cachedGuide;
  cachedGuide = fs.readFileSync(filePath, "utf8");
  guideMtime = stat.mtimeMs;
  return cachedGuide;
}

async function askModel(input, cfg = config) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs);
  try {
    const response = await fetch(`${cfg.ollamaUrl}/api/chat`, {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: cfg.model,
        stream: false,
        think: false,
        keep_alive: "30m",
        format: decisionSchema,
        options: { temperature: 0.15, num_predict: 130 },
        messages: [
          { role: "system", content: readGuide(cfg.rulesFile) },
          { role: "user", content: JSON.stringify(input) }
        ]
      })
    });
    if (!response.ok) throw Error(`Ollama HTTP ${response.status}`);
    const result = await response.json();
    return parseModelDecision(result?.message?.content);
  } finally {
    clearTimeout(timer);
  }
}

function createBackend(cfg = config, modelFn = askModel) {
  let active = 0;
  const server = net.createServer(socket => {
    socket.setEncoding("utf8");
    socket.setNoDelay(true);
    socket.setTimeout(cfg.timeoutMs + 5000);
    let bytes = 0;
    let buffer = "";
    let handled = false;
    const reply = (value) => {
      if (!socket.destroyed) socket.end(JSON.stringify(value) + "\n");
    };
    socket.on("timeout", () => socket.destroy());
    socket.on("error", error => console.warn("[MEX AI] tcp", error.message));
    socket.on("data", async chunk => {
      if (handled) return;
      bytes += Buffer.byteLength(chunk, "utf8");
      if (bytes > cfg.maxBytes) { handled = true; reply({ type: "error", error: "request_too_large" }); return; }
      buffer += chunk;
      const pos = buffer.indexOf("\n");
      if (pos < 0) return; // TCP has no message boundaries.
      handled = true; // One request per connection; prevents duplicate execution.
      const raw = buffer.slice(0, pos);
      let message;
      try { message = JSON.parse(raw); } catch { reply({ type: "error", error: "invalid_json" }); return; }
      if (message?.v === 1 && message?.type === "ping") {
        reply({ v: 1, type: "pong", id: sanitizeText(message.id, 64), model: cfg.model });
        return;
      }
      let input;
      try { input = normalizeRequest(message); }
      catch (e) { reply({ type: "error", id: sanitizeText(message?.id, 64), error: e.message }); return; }
      if (active >= cfg.maxActive) {
        reply(safeDecision(input, null, "busy"));
        return;
      }
      active++;
      try {
        const rawDecision = await modelFn(input, cfg);
        reply(safeDecision(input, rawDecision));
      } catch (e) {
        console.warn(`[MEX AI] request ${input.id}: ${e.message}`);
        reply(safeDecision(input, null, "ollama_error"));
      } finally {
        active--;
      }
    });
  });
  return server;
}

if (require.main === module) {
  const server = createBackend();
  server.listen(config.port, config.host, () => {
    console.log(`[MEX AI] listening ${config.host}:${config.port}`);
    console.log(`[MEX AI] Ollama ${config.ollamaUrl} model=${config.model}`);
    console.log(`[MEX AI] rules ${config.rulesFile}`);
  });
}
module.exports = { createBackend, normalizeRequest, envelope, safeDecision, parseModelDecision, config };