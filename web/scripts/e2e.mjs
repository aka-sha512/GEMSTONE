// end-to-end ui test: headless firefox over webdriver bidi, real pointer and keyboard input
// (react native's pressable reacts to pointer events, not synthetic clicks)
// needs a running server (julia --project=. run.jl)
//   pnpm e2e                                              test http://127.0.0.1:8000
//   PORT=8765 pnpm e2e -- --shots ../docs/screenshots     also save the documentation screenshots
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const BASE = `http://127.0.0.1:${process.env.PORT || 8000}/`;
const shotsArg = process.argv.indexOf("--shots");
const SHOTS = shotsArg > 0 ? process.argv[shotsArg + 1] : null;

const profile = mkdtempSync(join(tmpdir(), "gemstone-ff-"));
const ff = spawn("firefox", ["--headless", "--no-remote", "--profile", profile, "--remote-debugging-port", "9224"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const finish = (code) => { ff.kill(); setTimeout(() => { rmSync(profile, { recursive: true, force: true }); process.exit(code); }, 500); };
const fail = (msg) => { console.error("failed:", msg); finish(1); };
process.on("unhandledRejection", (e) => fail(e.message));
process.on("uncaughtException", (e) => fail(e.message));

// ---------- webdriver bidi plumbing ----------
let ws;
for (let i = 0; i < 60 && !ws; i++) {
  await sleep(500);
  try { ws = await new Promise((res, rej) => { const s = new WebSocket("ws://127.0.0.1:9224/session"); s.onopen = () => res(s); s.onerror = rej; }); } catch {}
}
if (!ws) fail("cannot connect to firefox");
let nextId = 0;
const pending = new Map();
ws.onmessage = (m) => { const msg = JSON.parse(m.data); pending.get(msg.id)?.(msg); pending.delete(msg.id); };
const send = (method, params) => new Promise((res, rej) => {
  const id = ++nextId;
  pending.set(id, (m) => (m.type === "error" ? rej(new Error(`${method}: ${m.message}`)) : res(m.result)));
  ws.send(JSON.stringify({ id, method, params }));
});
await send("session.new", { capabilities: {} });
const { context } = await send("browsingContext.create", { type: "tab" });
const viewport = (width, height) => send("browsingContext.setViewport", { context, viewport: { width, height } });
const js = async (expression) => (await send("script.evaluate", { expression, target: { context }, awaitPromise: true })).result.value;

// ---------- page helpers ----------
/** Centre of the first visible element whose own text (or SVG text) equals `text`. */
const locate = (text, svg) => js(`(() => {
  const own = (el) => ${svg ? "el.textContent" : "[...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('')"};
  const el = [...document.querySelectorAll(${svg ? '"svg text"' : '"div, span, a"'})]
    .find((el) => own(el).trim() === ${JSON.stringify(text)} && el.getBoundingClientRect().width > 0);
  if (!el) return null;
  el.scrollIntoView({ block: "center" });
  const r = el.getBoundingClientRect();
  return JSON.stringify([Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)]);
})()`);
const inputAt = (placeholder) => js(`(() => {
  const el = [...document.querySelectorAll("input")].find((e) => e.placeholder === ${JSON.stringify(placeholder)} && e.getBoundingClientRect().width > 0);
  if (!el) return null;
  el.scrollIntoView({ block: "center" });
  const r = el.getBoundingClientRect();
  return JSON.stringify([Math.round(r.x + 10), Math.round(r.y + r.height / 2)]);
})()`);
async function pointerAt(where, what) {
  let at = null;
  for (let i = 0; i < 50 && !at; i++) { at = await where(); if (!at) await sleep(200); }
  if (!at) return fail(`cannot find ${what}`);
  at = JSON.parse(at);
  await send("input.performActions", { context, actions: [{ type: "pointer", id: "mouse", parameters: { pointerType: "mouse" }, actions: [
    { type: "pointerMove", x: at[0], y: at[1] }, { type: "pointerDown", button: 0 }, { type: "pause", duration: 40 }, { type: "pointerUp", button: 0 },
  ] }] });
  await sleep(250);
}
const click = (text, svg = false) => pointerAt(() => locate(text, svg), `"${text}"`);
const keys = (sequence) => send("input.performActions", { context, actions: [{ type: "key", id: "kbd", actions: sequence }] });
const press = (...chars) => keys(chars.flatMap((c) => [{ type: "keyDown", value: c }, { type: "keyUp", value: c }]));
async function typeInto(placeholder, text, enter = false) {
  await pointerAt(() => inputAt(placeholder), `input "${placeholder}"`);
  await keys([{ type: "keyDown", value: "" }, { type: "keyDown", value: "a" }, { type: "keyUp", value: "a" }, { type: "keyUp", value: "" }]);
  await press(...text, ...(enter ? [""] : []));
  await sleep(300);
}
async function expect(text, what) {
  for (let i = 0; i < 60; i++) {
    if (await js(`document.body.innerText.includes(${JSON.stringify(text)})`)) return console.log("ok  ", what);
    await sleep(200);
  }
  fail(`${what}: "${text}" never appeared`);
}
async function shot(name, width = 1440, height = 1000) {
  if (!SHOTS) return;
  await viewport(width, height);
  await js("window.scrollTo(0, 0), document.querySelectorAll('*').forEach((e) => e.scrollTop && (e.scrollTop = 0))");
  await sleep(600);
  const { data } = await send("browsingContext.captureScreenshot", { context });
  writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(data, "base64"));
  await viewport(1440, 1000);
  console.log("shot", name);
}

// ---------- the test ----------
await viewport(1440, 1000);
await send("browsingContext.navigate", { context, url: BASE, wait: "complete" });
await expect("Phosphofructokinase", "app loads with the reaction list");
await click("toy_glucose.xml"); await expect("Teaching GEM", "example link loads the toy model");
await click("e_coli_core.json"); await expect("fba: not run", "e_coli_core reloaded (clean state)");

await typeInto("search reactions, metabolites or genes: PFK, pyruvate, pfkA", "pfkA");
await expect("b1723 or b3916", "gene-name search finds PFK and shows its gpr");
await click("f6p_c"); await expect("D-Fructose 6-phosphate", "metabolite link in the equation opens it");

await click("pathways");
await typeInto("target product: succ_c", "succ_");
await click("succ_c"); await expect("shortest routes from glc__D_e", "suggestion runs the route search");
await shot("3-product-pathways", 1440, 1500);
await click("pep_c", true); await expect("Phosphoenolpyruvate", "clicking a graph node opens that metabolite");
await click("PYK"); await expect("Pyruvate kinase", "reaction link opens the reaction");

await click("fba");
await click("run fba"); await expect("0.873922", "fba: aerobic growth");
await typeInto("objective reaction", "ATPM");
await click("run fba"); await expect("ATPM =", "fba: another objective (atp maintenance)");
await typeInto("objective reaction", "BIOMASS_Ecoli_core_w_GAM");
await click("run fba"); await expect("0.873922", "fba: back to growth");
await shot("5-flux-balance");

if (SHOTS) {
  await click("reactions"); await typeInto("search reactions, metabolites or genes: PFK, pyruvate, pfkA", "PFK");
  await expect("flux 7.4", "PFK shows its flux"); await shot("1-reaction-search");
  await click("metabolites"); await typeInto("metabolite: pyr_c", "pyr_c", true); await expect("Pyruvate", "pyruvate view");
  await shot("2-metabolite-network", 1440, 1100);
  await click("pathways"); await click("fba flux only"); await click("find routes"); await sleep(800);
  await shot("4-pathways-fba-flux", 1440, 1500);
  await click("metabolites"); await shot("6-phone-layout", 390, 844);
}
console.log("all ui checks passed");
finish(0);
