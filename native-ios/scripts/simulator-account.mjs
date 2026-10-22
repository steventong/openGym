// Local integration-test account, created through the unmodified public API.
// This software WebAuthn credential follows api/test/server-first-user-admin.test.js.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const origin = 'http://localhost:8080';
const file = path.join(root,'.test-session.json');
const b64 = b => Buffer.from(b).toString('base64url');
const sha = b => crypto.createHash('sha256').update(b).digest();
const head = (m,n) => n<24 ? Buffer.from([(m<<5)|n]) : n<256 ? Buffer.from([(m<<5)|24,n]) : Buffer.from([(m<<5)|25,n>>8,n&255]);
const txt = s => Buffer.concat([head(3,Buffer.byteLength(s)),Buffer.from(s)]);
const bytes = b => Buffer.concat([head(2,b.length),b]);
async function req(route, body, token, method) {
 const response = await fetch(origin+route,{method:method || (body ? 'POST':'GET'),headers:{'Content-Type':'application/json',Origin:origin,...(token ? {Authorization:'Bearer '+token}: {})},...(body ? {body:JSON.stringify(body)}:{})});
 const json=await response.json(); if(!response.ok) throw new Error(route+' HTTP '+response.status+': '+json.error);
 return {json,response};
}
let saved;
if(fs.existsSync(file)) saved=JSON.parse(fs.readFileSync(file,'utf8'));
if(!saved) {
 const opt=(await req('/api/register/options',{name:'iOS 模拟器测试'})).json;
 const {publicKey}=crypto.generateKeyPairSync('ec',{namedCurve:'P-256'});
 const jwk=publicKey.export({format:'jwk'});
 const cose=Buffer.concat([Buffer.from([0xa5,0x01,0x02,0x03,0x26,0x20,0x01,0x21,0x58,0x20]),Buffer.from(jwk.x,'base64url'),Buffer.from([0x22,0x58,0x20]),Buffer.from(jwk.y,'base64url')]);
 const raw=crypto.randomBytes(16), id=b64(raw);
 const auth=Buffer.concat([sha('localhost'),Buffer.from([0x45]),Buffer.alloc(4),Buffer.alloc(16),Buffer.from([0,raw.length]),raw,cose]);
 const att=Buffer.concat([Buffer.from([0xa3]),txt('fmt'),txt('none'),txt('attStmt'),Buffer.from([0xa0]),txt('authData'),bytes(auth)]);
 const credential={id,rawId:id,type:'public-key',clientExtensionResults:{},authenticatorAttachment:'platform',response:{clientDataJSON:b64(JSON.stringify({type:'webauthn.create',challenge:opt.options.challenge,origin,crossOrigin:false})),attestationObject:b64(att),transports:['internal']}};
 const registration=await req('/api/register/verify',{cid:opt.cid,credential});
 const cookie=registration.response.headers.get('set-cookie');
 const token=cookie.match(/gymsid=([^;]+)/)[1];
 saved={token,user:registration.json.user}; fs.writeFileSync(file,JSON.stringify(saved),{mode:0o600});
 const routine={id:crypto.randomUUID(),name:'上肢训练 · 模拟器测试',emoji:'barbell',ex:[{id:'0150',sets:3,reps:10,weight:20},{id:'0025',sets:3,reps:10,weight:20},{id:'0031',sets:3,reps:12,weight:10}]};
 await req('/api/data',{baseRev:0,state:{unit:'kg',lang:'zh',restSec:90,theme:'dark',routines:[routine],week:{[new Date().getDay()]:routine.id},workouts:[],bodyweight:[],nativeTestSentinel:{keep:'unknown fields must survive native writes'}}},token,'PUT');
}
const {json}=await req('/api/pair/create',{},saved.token);
const sim=process.argv[2];
if(!sim) throw new Error('Pass an explicit simulator UDID');
execFileSync('xcrun',['simctl','launch',sim,'com.opengym.native.preview','-pairCode',json.code],{stdio:'pipe'});
console.log('Launched native app and paired the isolated iOS simulator test account through /api/pair/redeem.');
