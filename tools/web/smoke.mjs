// Browser smoke for an already staged Pages build, not a build or server.
// Run: node tools/web/smoke.mjs http://127.0.0.1:8000/order-of-last-resort/
// Requires Chromium, Tesseract, and Node with global WebSocket (Node 22+).
// Uses a fresh, disposable Chromium profile, never the player's browser data.
import { spawn, spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const url = new URL(process.argv[2]);
if (url.pathname !== "/order-of-last-resort/" || url.search || url.hash) {
  throw new Error("Pass the staged /order-of-last-resort/ directory URL, without query or fragment");
}
// Check the staging path before starting Chromium so an absent export reports
// the actual HTTP failure and cannot leave a browser behind.
const entry = await fetch(url, { redirect: "manual" });
if (entry.status !== 200) throw new Error(`Entry request ${url} returned ${entry.status}`);
const guild = "Smoke Company";
const temp = await mkdtemp(join(tmpdir(), "olr-pages-smoke-"));
const browser = spawn(process.env.CHROMIUM ?? "chromium", [
  "--headless=new", "--no-sandbox", "--disable-dev-shm-usage",
  "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
  "--remote-debugging-port=0", `--user-data-dir=${temp}`, "about:blank",
], { stdio: "ignore" });
let socket;

try {
  let devtools;
  for (let i = 0; i < 100 && !devtools; i++) {
    if (browser.exitCode !== null) throw new Error("Chromium exited before opening DevTools");
    try { devtools = (await readFile(join(temp, "DevToolsActivePort"), "utf8")).trim().split("\n"); }
    catch { await delay(100); }
  }
  if (!devtools || devtools.length < 2) throw new Error("Chromium DevTools did not start");
  socket = new WebSocket(`ws://127.0.0.1:${devtools[0]}${devtools[1]}`);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
  let sequence = 0;
  const pending = new Map();
  const assets = new Map();
  const artifactRequests = new Map();
  const coldBytes = new Map();
  const failures = [];
  let cold = true;
  socket.addEventListener("message", event => {
    const message = JSON.parse(event.data);
    if (message.id) {
      const request = pending.get(message.id);
      if (!request) return;
      pending.delete(message.id);
      if (message.error) request.reject(new Error(`${request.method}: ${message.error.message}`));
      else request.resolve(message.result);
    } else if (message.method === "Network.responseReceived") {
      const response = message.params.response;
      const resource = new URL(response.url);
      if (resource.origin === url.origin && /\.(?:js|wasm|pck)$/i.test(resource.pathname)) {
        assets.set(resource.pathname, response.status);
        if (cold) artifactRequests.set(message.params.requestId, resource.pathname);
        if (resource.pathname === `${url.pathname}index.wasm` &&
            response.mimeType.toLowerCase() !== "application/wasm") {
          failures.push(`incorrect WebAssembly MIME type: ${response.mimeType}`);
        }
        if (!resource.pathname.startsWith(url.pathname) || response.status < 200 || response.status >= 300) {
          failures.push(`${response.status} ${response.url}`);
        }
      }
    } else if (message.method === "Network.loadingFinished") {
      const path = artifactRequests.get(message.params.requestId);
      if (path) {
        coldBytes.set(path, (coldBytes.get(path) ?? 0) + message.params.encodedDataLength);
        artifactRequests.delete(message.params.requestId);
      }
    } else if (message.method === "Network.loadingFailed" && !message.params.canceled) {
      failures.push(`network failure: ${message.params.errorText}`);
    } else if (message.method === "Page.javascriptDialogOpening") {
      console.error(`Browser dialog (${message.params.type}): ${message.params.message}`);
      call("Page.handleJavaScriptDialog", { accept: true }).catch(error => failures.push(error.message));
    }
  });
  let sessionId;
  function call(method, params = {}, browserCommand = false) {
    const id = ++sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`${method}: DevTools did not respond within 30 seconds`));
      }, 30000);
      pending.set(id, {
        resolve: result => { clearTimeout(timer); resolve(result); },
        reject: error => { clearTimeout(timer); reject(error); },
        method,
      });
      socket.send(JSON.stringify({ id, method, params, ...(!browserCommand && sessionId ? { sessionId } : {}) }));
    });
  }
  let target = await call("Target.createTarget", { url: "about:blank" }, true);
  ({ sessionId } = await call("Target.attachToTarget", { targetId: target.targetId, flatten: true }, true));
  await call("Page.enable");
  await call("Network.enable");
  await call("Emulation.setDeviceMetricsOverride", {
    width: 1280, height: 820, deviceScaleFactor: 1, mobile: false,
  });
  await call("Page.navigate", { url: url.href });

  async function readScreen(psm = "11") {
    let shot;
    for (let attempt = 0; attempt < 100; attempt++) {
      try {
        shot = await call("Page.captureScreenshot", { format: "png" });
        break;
      } catch (error) {
        if (!error.message.includes("Not attached to an active page")) throw error;
        await delay(100);
      }
    }
    if (!shot) throw new Error("Chromium page never became active after navigation");
    if (process.env.SMOKE_SCREENSHOT) {
      await writeFile(process.env.SMOKE_SCREENSHOT, Buffer.from(shot.data, "base64"));
    }
    const ocr = spawnSync("tesseract", ["stdin", "stdout", "--psm", psm, "tsv"], {
      input: Buffer.from(shot.data, "base64"), maxBuffer: 10 * 1024 * 1024,
    });
    if (ocr.error || ocr.status !== 0) throw new Error(`Tesseract failed: ${ocr.error ?? ocr.stderr}`);
    return ocr.stdout.toString().split("\n").slice(1).map(line => {
      const fields = line.split("\t");
      return { line: fields.slice(0, 5).join(":"), x: Number(fields[6]), y: Number(fields[7]),
        width: Number(fields[8]), height: Number(fields[9]), text: fields[11] ?? "" };
    }).filter(word => word.text);
  }
  const normalize = text => text.toLowerCase().replace(/[^a-z0-9]/g, "");
  function find(words, phrase, last = false) {
    const wanted = phrase.split(" ").map(normalize);
    const matches = [];
    for (let i = 0; i <= words.length - wanted.length; i++) {
      const match = words.slice(i, i + wanted.length);
      if (match.every((word, j) => word.line === match[0].line && normalize(word.text) === wanted[j])) {
        const first = match[0], last = match.at(-1);
        matches.push({ x: (first.x + last.x + last.width) / 2, y: first.y + first.height / 2 });
      }
    }
    matches.sort((a, b) => a.y - b.y);
    return (last ? matches.at(-1) : matches[0]) ?? null;
  }
  async function waitFor(phrase, timeout = 90000, last = false) {
    const deadline = Date.now() + Math.min(timeout, Number(process.env.SMOKE_TIMEOUT_MS ?? timeout));
    let words = [];
    while (Date.now() < deadline) {
      words = await readScreen();
      const position = find(words, phrase, last);
      if (position) return position;
      await delay(500);
    }
    throw new Error(`Did not see "${phrase}". Last screen OCR: ${words.map(w => w.text).join(" ")}`);
  }
  async function click(position) {
    for (const type of ["mousePressed", "mouseReleased"]) {
      await call("Input.dispatchMouseEvent", { type, ...position, button: "left", clickCount: 1 });
    }
  }
  async function key(key, code, windowsVirtualKeyCode) {
    for (const type of ["keyDown", "keyUp"]) {
      await call("Input.dispatchKeyEvent", { type, key, code, windowsVirtualKeyCode });
    }
  }
  async function typeText(text) {
    for (const char of text) {
      const code = char === " " ? "Space" : `Key${char.toUpperCase()}`;
      const windowsVirtualKeyCode = char === " " ? 32 : char.toUpperCase().charCodeAt(0);
      await call("Input.dispatchKeyEvent", {
        type: "keyDown", key: char, code, windowsVirtualKeyCode, text: char,
      });
      await call("Input.dispatchKeyEvent", { type: "keyUp", key: char, code, windowsVirtualKeyCode });
    }
  }

  await waitFor("Name your guild");
  // The game focuses its name field on opening. Enter submits the actual form.
  await typeText(guild);
  await key("Enter", "Enter", 13);
  await waitFor("Standing orders");
  // The lesson requires setting Blast, staging a move, opening Forecast, and
  // committing. Select controls by their printed labels, not private game state.
  await click(await waitFor("Standing orders", 90000, true));
  // Practice starts Pip on Hold position. PSM 6 reads the selected dropdown
  // text on the parchment more reliably than the sparse-text mode.
  const orderWords = await readScreen("6");
  const hold = orderWords.filter(w =>
    w.x > 800 && w.y > 350 && w.y < 700 && normalize(w.text) === "hold");
  if (hold.length !== 1) {
    throw new Error(`Expected one Hold position control in Standing orders, found ${hold.length}`);
  }
  await click({ x: hold[0].x + hold[0].width / 2, y: hold[0].y + hold[0].height / 2 });
  await click(await waitFor("Blast nearest", 90000, true));
  await waitFor("Give one direct command");
  await click(await waitFor("Standing orders", 90000, true));

  // Practice places the Caster at F3 with F2 empty. These are cell centres
  // at the fixed 1280x820 viewport, with the orders sheet closed. OCR cannot
  // reliably read the small, textured axis labels. The lesson-state checks
  // below ensure a layout change cannot silently turn this into a false pass.
  await click({ x: 856, y: 438 });
  await click({ x: 856, y: 347 });
  await waitFor("Compare and commit");
  await click(await waitFor("Forecast", 90000, true));
  await waitFor("moves to F2");
  // Tesseract misses the gold commit button on the textured footer.
  await click({ x: 1130, y: 770 });
  await waitFor("See the standing order return");
  console.log("PASS: staged a Caster move and committed practice round 1");
  await click({ x: 115, y: 127 });
  await waitFor("Replay practice");
  await waitFor(guild);
  console.log("PASS: created a guild, entered practice and skipped to the commission board");

  cold = false;
  const loaded = new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.removeEventListener("message", onMessage);
      reject(new Error("Reload did not fire the page load event"));
    }, 30000);
    function onMessage(event) {
      const message = JSON.parse(event.data);
      if (message.sessionId !== sessionId || message.method !== "Page.loadEventFired") return;
      clearTimeout(timer);
      socket.removeEventListener("message", onMessage);
      resolve();
    }
    socket.addEventListener("message", onMessage);
  });
  await call("Page.reload", { ignoreCache: true });
  await loaded;
  await waitFor("Replay practice");
  await waitFor(guild);
  console.log("PASS: reload retained the guild and returned to the board");
  await click(await waitFor("Replay practice"));
  await waitFor("Standing orders");
  await click({ x: 115, y: 127 });
  await waitFor("Replay practice");
  console.log("PASS: replayed and skipped practice");

  for (const ext of ["js", "wasm", "pck"]) {
    const path = `${url.pathname}index.${ext}`;
    const status = assets.get(path);
    if (!(status >= 200 && status < 300)) {
      throw new Error(`No successful ${path} export request; observed: ${JSON.stringify([...assets])}`);
    }
  }
  if (failures.length) throw new Error(`Failed or misplaced requests: ${failures.join("; ")}`);
  console.log(`PASS: export artifacts requested successfully: ${JSON.stringify([...assets])}`);
  console.log(`Cold transfer bytes reported by Chromium, when available: ${JSON.stringify([...coldBytes])}`);
  console.log("NOT CHECKED: audible output and subjective visual quality require a human review");
} finally {
  socket?.close();
  if (browser.exitCode === null) {
    const exited = new Promise(resolve => browser.once("exit", resolve));
    browser.kill();
    await exited;
  }
  // Chromium descendants can briefly hold profile files after the browser exits.
  // Cleanup failure must not mask the test's actual assertion or HTTP error.
  try { await rm(temp, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); }
  catch (error) { console.error(`Could not remove disposable Chromium profile ${temp}: ${error}`); }
}
