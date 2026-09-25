const CONFIG_KEY = "hapd_config";
const DEFAULTS = { ha_ip: "", ha_port: 8123, mobile_notify_service: "", token: "", log_mode: "off" };
const ids = ["ha_ip","ha_port","mobile_notify_service","token","log_mode"];
const el = Object.fromEntries(ids.map(id => [id, document.getElementById(id)]));
const statusEl = document.getElementById("status");
let lastValid = null;
let saveTimer = null;
let connectionSocket = null;
let connected = false;

function readForm() {
  return {
    ha_ip: el.ha_ip.value.trim(),
    ha_port: Number(el.ha_port.value),
    mobile_notify_service: el.mobile_notify_service.value.trim(),
    token: el.token.value.trim(),
    log_mode: el.log_mode.value
  };
}
function validate(c) {
  return c.ha_ip.length > 0 && Number.isInteger(c.ha_port) && c.ha_port >= 1 && c.ha_port <= 65535 &&
    c.mobile_notify_service.startsWith("notify.") && c.token.length > 0 &&
    ["off","phone","single","all"].includes(c.log_mode);
}
function markValidity(c) {
  el.ha_ip.classList.toggle("invalid", !c.ha_ip);
  el.ha_port.classList.toggle("invalid", !(Number.isInteger(c.ha_port) && c.ha_port>=1 && c.ha_port<=65535));
  el.mobile_notify_service.classList.toggle("invalid", !c.mobile_notify_service.startsWith("notify."));
  el.token.classList.toggle("invalid", !c.token);
}
function setStatus(text, cls="") { statusEl.textContent=text; statusEl.className=`status ${cls}`; }
async function saveIfValid() {
  const c=readForm(); markValidity(c);
  if (!validate(c)) { setStatus("Configuration is incomplete. Last valid configuration remains active.","error"); return false; }
  await chrome.storage.local.set({[CONFIG_KEY]:c});
  lastValid=c;
  chrome.runtime.sendMessage({type:"config-changed"}).catch(()=>{});
  setStatus("Configuration saved automatically.","ok");
  return true;
}
function scheduleSave(){ clearTimeout(saveTimer); saveTimer=setTimeout(saveIfValid,250); }
async function load(){
  const stored=await chrome.storage.local.get(CONFIG_KEY);
  const c={...DEFAULTS,...(stored[CONFIG_KEY]||{})};
  ids.forEach(id=>el[id].value=c[id]);
  lastValid=validate(c)?c:null;
  markValidity(c);
  setStatus(lastValid?"Configuration loaded.":"Complete the connection parameters.",lastValid?"ok":"");
}
async function disconnectConnection() {
  if (connectionSocket) {
    try { connectionSocket.close(); } catch {}
    connectionSocket = null;
  }
  connected = false;
  const button = document.getElementById("connect");
  button.disabled = false;
  button.textContent = "Connect";
  setStatus("Disconnected from Home Assistant.", "");
}

async function testConnection(){
  if (connected) { await disconnectConnection(); return; }
  if(!await saveIfValid()) return;
  const c=readForm();
  const button=document.getElementById("connect");
  button.disabled=true; button.textContent="Connecting…"; setStatus("Connecting to Home Assistant…","busy");
  let timer;
  try{
    await new Promise((resolve,reject)=>{
      const socket=new WebSocket(`ws://${c.ha_ip}:${c.ha_port}/api/websocket`);
      connectionSocket=socket;
      timer=setTimeout(()=>reject(new Error("Connection timeout.")),8000);
      socket.onerror=()=>reject(new Error("WebSocket connection failed."));
      socket.onclose=()=>{
        if (connectionSocket === socket) {
          connectionSocket=null;
          connected=false;
          button.disabled=false;
          button.textContent="Connect";
        }
      };
      socket.onmessage=e=>{
        let msg; try{msg=JSON.parse(e.data)}catch{return}
        if(msg.type==="auth_required") socket.send(JSON.stringify({type:"auth",access_token:c.token}));
        else if(msg.type==="auth_invalid") reject(new Error(msg.message||"Authentication failed."));
        else if(msg.type==="auth_ok") resolve();
      };
    });
    clearTimeout(timer);
    connected=true;
    setStatus("Connected to Home Assistant.","ok");
    button.textContent="Disconnect";
    button.disabled=false;
  }catch(error){
    clearTimeout(timer);
    if(connectionSocket) try{connectionSocket.close()}catch{}
    connectionSocket=null; connected=false;
    setStatus(error.message,"error"); button.textContent="Connect"; button.disabled=false;
  }
}
ids.forEach(id=>{el[id].addEventListener(id==="log_mode"?"change":"input",scheduleSave)});
document.getElementById("show_token").addEventListener("click",e=>{
  const show=el.token.type==="password"; el.token.type=show?"text":"password"; e.currentTarget.textContent=show?"Hide":"Show";
});
document.getElementById("reset").addEventListener("click",()=>{
  ids.forEach(id=>el[id].value=DEFAULTS[id]); markValidity(readForm());
  setStatus("Form reset. Last valid configuration remains active until new valid values are entered.","busy");
});
document.getElementById("connect").addEventListener("click",testConnection);
document.getElementById("close").addEventListener("click",()=>{ if(connectionSocket) try{connectionSocket.close()}catch{} window.close(); });
load();
