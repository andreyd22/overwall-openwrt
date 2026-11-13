'use strict';
// DOM behavior tests only. These do not replace real-browser visual acceptance.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const browser = new JSDOM('<!doctype html><body></body>', { url: 'http://router.invalid/' });
const { document } = browser.window;
global.window = browser.window; global.document = document; global.Event = browser.window.Event;
window.confirm = () => true;
let state = { state: 'disconnected', network: 'lan', sources: [], signed_in: false, autostart: false };
const commands = [], jobs = new Map(), notices = [];
let pairURL = 'https://overwall.online/client/tv/activate?id=fixture';
function E(tag, attrs, content) {
  const element = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs || {})) {
    if (typeof value === 'function') element.addEventListener(key, value);
    else if (key === 'checked') element.checked = !!value;
    else if (value != null) element.setAttribute(key, value);
  }
  function append(value) {
    if (Array.isArray(value)) return value.forEach(append);
    if (value != null) element.append(value?.nodeType ? value : document.createTextNode(String(value)));
  }
  append(content); return element;
}
const poll = { add() {}, remove() {} };
const ui = {
  createHandlerFn: (context, fn) => event => fn.call(context, event),
  addNotification: (_, message) => notices.push(message.textContent),
  showModal: (title, nodes) => { let modal = document.getElementById('test-modal'); if (modal) modal.remove(); modal = E('div', { id: 'test-modal' }, [E('h2', {}, title), nodes]); document.body.append(modal); },
  hideModal: () => document.getElementById('test-modal')?.remove()
};
const rpc = { declare: spec => async (...args) => {
  if (spec.method === 'status') return structuredClone(state);
  if (spec.method === 'job') return { done: true, result: jobs.get(args[0]) };
  const [action, data] = args; commands.push({ action, data: JSON.parse(data) });
  const id = String(commands.length);
  jobs.set(id, action === 'pair' ? { user_code: 'FIXTURE', verification_uri: pairURL, expires_in: 300, poll_interval: 5, qr_svg: '<svg xmlns="http://www.w3.org/2000/svg"></svg>' } : { success: true });
  return { job_id: id };
} };
const L = { resource: value => '/luci-static/resources/' + value, bind: (fn, self) => fn.bind(self) };
const dom = { content: (element, content) => element.replaceChildren(...content) };
const source = fs.readFileSync(path.join(__dirname, '../packages/luci-app-overwall/htdocs/luci-static/resources/view/overwall.js'), 'utf8');
const screen = new Function('view', 'rpc', 'ui', 'poll', 'network', 'dom', 'L', 'E', '_', source)(
  { extend: value => value }, rpc, ui, poll, {}, dom, L, E, value => value
);
async function click(label) {
  const button = [...document.querySelectorAll('button')].find(b => b.textContent === label);
  assert.ok(button, `missing control ${label}`);
  button.click(); await new Promise(resolve => setImmediate(resolve));
}
(async () => {
  document.body.append(screen.render([state, [{ getName: () => 'lan' }, { getName: () => 'wan' }]]));
  assert.match(document.body.textContent, /Добавьте ссылку|Добавьте своё|Добавьте|Войдите в аккаунт Overwall/);
  assert.equal(document.querySelector('select option[value="wan"]'), null);
  await click('＋ Своё подключение');
  const modal = document.getElementById('test-modal');
  modal.querySelector('input[name="source-name"]').value = 'Independent fixture';
  modal.querySelector('select').value = 'wireguard';
  modal.querySelector('textarea').value = 'fixture config, not a real key';
  await click('Добавить подключение');
  assert.deepEqual(commands.at(-1), { action: 'add', data: { name: 'Independent fixture', kind: 'wireguard', value: 'fixture config, not a real key' } });
  state.sources = [{ id: 'fixture', name: '<img src=x onerror=alert(1)>', kind: 'wireguard', nodes: [{ name: 'Fixture WG', protocol: 'wireguard' }] }];
  await screen.update(); screen.setTab('wireguard');
  assert.equal(screen.root.querySelector('img'), null, 'provider names must be text');
  await click('Подключить');
  assert.deepEqual(commands.at(-1), { action: 'connect', data: { id: 'fixture', node: 0 } });
  await click('Войти в аккаунт');
  assert.match(document.getElementById('test-modal').querySelector('img').src, /^data:image\/svg\+xml;base64,/);
  assert.equal(document.getElementById('test-modal').querySelector('a').origin, 'https://overwall.online');
  ui.hideModal(); pairURL = 'https://attacker.invalid/client/tv/activate?id=fixture';
  await assert.rejects(screen.pairDialog(), /Некорректный адрес/);
  assert.equal(notices.length, 0);
  screen.setTab('settings');
  assert.equal(screen.root.querySelector('input[type=checkbox]').checked, false, 'false autostart must stay unchecked');
  screen.root.querySelector('input[type=checkbox]').click();
  await click('Сохранить настройки');
  assert.equal(commands.at(-1).data.autostart, true);
  assert.equal(screen.root.querySelector('select').value, 'lan');
  console.log('PASS: LuCI empty state, source import, queued connect, escaped names, local QR and fixed pairing origin');
  browser.window.close();
})().catch(error => { console.error(error); process.exitCode = 1; });
