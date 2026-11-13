'use strict';
// Isolated integration fixture. Never deploy this server or its login stub.
const fs = require('node:fs');
const https = require('node:https');
const express = require('/backend/node_modules/express');
const Redis = require('/backend/node_modules/ioredis');
const { createClientApi } = require('/backend/shared/clientApi');
const redis = new Redis(16379, '127.0.0.1');
const crypto = require('node:crypto');
const managed = JSON.parse(fs.readFileSync('/work/lab/managed-wg.json'));
const bindings = new Map([['3', {hash:'fixture-other-installation',name:'Телефон · тест',version:crypto.randomUUID()}]]);
const locations = ['🇺🇸 США · тест', '🇱🇻 Латвия · тест', '🇺🇸 БС полный · тест'];
function ownership(slot,session) {const binding=bindings.get(slot);return {state:!binding?'free':binding.hash===session.installationHash?'mine':'busy',name:binding?.name,version:binding?.version};}
const user = { id: 42, verified_email: 'fixture@example.invalid' };
let access = 'active', wireguardAccess = true;
const api = createClientApi({
  redis, publicOrigin: 'https://overwall.online', findUser: async id => String(id) === '42' ? user : null,
  resolveEmail: async () => user, sendEmail: async () => {},
  profile: async () => ({ id: '42', email: user.verified_email,
    access: { state: access, protocols: { vless: { state: access } }, total_bytes: 1073741824, remaining_bytes: access === 'active' ? 1073741824 : 0 },
    servers: access === 'active' ? ['🇦🇹 🛡️ Основной · тест','🇺🇸 ✨ Gemini · тест','🇱🇻 ▶ YouTube · тест'].map((name,index)=>({ id: 'fixture-vless-'+index, name, uri: 'vless://00000000-0000-4000-8000-000000000001@10.0.2.2:18443?security=none&type=tcp#Lab' })) : [] }),
  wireguard: {
    list: async (user,session) => ({ state: wireguardAccess ? 'available' : 'access_required', access: { state: wireguardAccess ? 'active' : 'access_required' }, traffic_unlimited: true,device_limit:3,profiles:managed.map((profile,index)=>({id:profile.id,name:'Тестовый профиль '+profile.id,location:locations[index],state:wireguardAccess?'available':'access_required',ownership:ownership(profile.id,session)})) }),
    assignment: async (user,id,action,session,input) => {
      if(!managed.some(p=>p.id===id))return {status:404,error:'profile_not_found'};
      const current=ownership(id,session);
      if(action==='claim') {
        if(!wireguardAccess)return {status:403,error:'wireguard_access_required'};
        if(current.state==='busy')return {status:409,error:'wireguard_device_busy'};
        if(current.state!=='mine')bindings.set(id,{hash:session.installationHash,name:session.label,version:crypto.randomUUID()});
      } else {
        if(current.state!=='mine'||current.version!==input.version)return {status:409,error:'wireguard_binding_changed'};
        bindings.delete(id);
      }
      return {status:200,ownership:ownership(id,session)};
    },
    configuration: async (user,id,session) => {
      if(!wireguardAccess)return {status:403,error:'wireguard_access_required'};
      if(ownership(id,session).state!=='mine')return {status:409,error:'wireguard_device_busy'};
      const profile=managed.find(p=>p.id===id);return profile?{status:200,id,configuration:profile.configuration}:{status:404,error:'profile_not_found'};
    }
  },
  webUser: async () => user, csrf: () => 'fixture-csrf', checkCsrf: req => req.body.csrf_token === 'fixture-csrf'
});
const app = express();
app.use(express.json());
app.use('/api/client/v1', api.router); app.use('/client', api.web);
app.get('/', (_, res) => res.type('html').send('<!doctype html><html><h1>Overwall isolated laboratory</h1><p>This is not production and creates no payments.</p></html>'));
https.createServer({ key: fs.readFileSync('/work/lab/tls/fixture.key'), cert: fs.readFileSync('/work/lab/tls/fixture.crt') }, app).listen(443, '0.0.0.0');
const control = express(); control.use(express.json());
control.post('/access', (req, res) => {
  if (!['active', 'traffic_exhausted', 'expired'].includes(req.body.state)) return res.sendStatus(400);
  access = req.body.state; wireguardAccess = req.body.wireguard !== false; res.json({ state: access, wireguard: wireguardAccess });
});
control.listen(19000, '127.0.0.1');
