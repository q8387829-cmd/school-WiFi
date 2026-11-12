import {createGlassSystem,createComponent} from './vendor/lens/index.js';
import {campusArtwork} from './campus-artwork.js';
import {connectionView,diagnosticView} from './model.js';
import {appearancePresets,appearanceStorageKey,loadAppearance,saveAppearance,scenePresets,loadScene,saveScene,resolveAppearanceMaterial,loadPanelFill,savePanelFill} from './appearance.js';

const $=id=>document.getElementById(id),stage=$('app'),main=$('main'),handles=[],controls={},pending=new Map(),hostPending=new Map(),errors=[];
const pages=['overview','account','diagnostics','logs'];
const carriers={campus:'校园网',unicom:'中国联通',cmcc:'中国移动',telecom:'中国电信'};
const paths={overview:'M3 10.5 12 3l9 7.5M5 9v11h14V9M9 20v-7h6v7',account:'M20 21v-2a7 7 0 0 0-14 0v2M13 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8',diagnostics:'m4 14 4-4 4 5 5-10 3 4M3 21h18',logs:'M6 3h12v18H6zM9 7h6M9 11h6M9 15h4',refresh:'M20 7v5h-5M4 17v-5h5M6 7a7 7 0 0 1 12-2l2 2M4 17l2 2a7 7 0 0 0 12-2',shield:'M12 3 4 6v6c0 5 8 9 8 9s8-4 8-9V6l-8-3Zm-4 9 3 3 5-6'};
let system,sequence=0,hostSequence=0,toastTimer=0,stateRequest=null,logsRequest=null,lastApplied=0,lastDiagnostic='';
function browserStorage(){try{return window.localStorage;}catch{return null;}}
const appearanceKey=appearanceStorageKey+(new URLSearchParams(location.search).has('verify')?'.verification':'');
const state={page:'overview',connected:false,started:false,actionBusy:false,formDirty:false,appearance:loadAppearance(browserStorage(),appearanceKey),panelFill:loadPanelFill(browserStorage(),appearanceKey+'.panelFill',appearanceKey),scene:loadScene(browserStorage(),appearanceKey+'.scene'),model:{},diagnostic:{Running:false,Result:null},logs:[],logsLoaded:false,logsBusy:false,search:'',filter:'all',mode:null};
function icon(name){const svg=document.createElementNS('http://www.w3.org/2000/svg','svg'),path=document.createElementNS(svg.namespaceURI,'path');for(const [key,value]of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.65','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true'}))svg.setAttribute(key,value);svg.classList.add('lg-icon');path.setAttribute('d',paths[name]||paths.overview);svg.append(path);return svg;}
function text(id,value){const element=$(id),next=String(value??'');if(element.textContent!==next)element.textContent=next;}
function component(host,type,props){const handle=createComponent(type,props);handles.push(handle);if(host)$(host).append(handle.element);return handle;}
function action(fn){return (...args)=>{void Promise.resolve().then(()=>fn(...args)).catch(error=>toast(error.message||'操作未完成，请稍后重试。'));};}
function button(host,label,fn,name){const handle=component(host,'button',{label,onPress:action(fn)}),copy=document.createElement('span');copy.textContent=label;handle.element.replaceChildren(...(name?[icon(name)]:[]),copy);handle.label=copy;return handle;}
function invalidate(duration=350){system?.renderer?.invalidate(duration);}
function toast(message){text('toast',message);$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>{$('toast').hidden=true;invalidate();},4000);invalidate();}
function send(value){window.chrome?.webview?.postMessage(value);}
function hostRequest(type,extra={}){return new Promise((resolve,reject)=>{const id=++hostSequence,timeout=setTimeout(()=>{hostPending.delete(id);reject(new Error('窗口未响应，请稍后再试。'));},10000);hostPending.set(id,{timeout,resolve});send({type,id,...extra});});}
function applyData(data,id){if(!data?.Model||id<lastApplied)return;lastApplied=id;state.model=data.Model;state.diagnostic=data.Diagnostic||{Running:false,Result:null};state.connected=true;renderConnection();renderAccount();renderDiagnostic();updateControls();if(data.Feedback)toast(data.Feedback);}
function disconnected(){state.connected=false;renderConnection();renderDiagnostic();updateControls();}
function invoke(command,payload){return new Promise((resolve,reject)=>{const id=++sequence,timeout=setTimeout(()=>{pending.delete(id);disconnected();reject(new Error('后台操作等待超时，请稍后重试。'));},30000);pending.set(id,{resolve,reject,timeout,command});send({type:'command',id,command,...(payload===undefined?{}:{payload})});});}
window.chrome?.webview?.addEventListener('message',event=>{
  const message=event.data;
  if(message.type==='result'){
    const request=pending.get(message.id);if(!request)return;pending.delete(message.id);clearTimeout(request.timeout);
    if(message.ok){applyData(message.data,message.id);request.resolve(message.data);}
    else{if(message.error?.code==='BackendUnavailable')disconnected();request.reject(new Error(message.error?.message||'操作未完成，请稍后重试。'));}
  }else if(message.type==='backend-ready'){
    state.started=true;state.mode={provider:message.provider,render:message.render};
    void refreshState().catch(error=>{disconnected();toast(error.message);});
  }else if(message.type==='backend-status'&&!message.connected){state.started=true;disconnected();}
  else if(message.type==='capture-complete'||message.type==='resize-complete'){const request=hostPending.get(message.id);if(request){clearTimeout(request.timeout);request.resolve();hostPending.delete(message.id);}}
  else if(message.type==='navigate'){showPage(message.page);if(state.started)void refreshState().catch(()=>{});}
  else if(message.type==='refresh'&&state.started){void refreshState().catch(()=>{});}
  else if(message.type==='host-notice'){toast(message.message);}
});
window.addEventListener('error',event=>errors.push(event.message));
window.addEventListener('unhandledrejection',event=>errors.push(String(event.reason)));
function refreshState(){if(stateRequest)return stateRequest;stateRequest=invoke('GetState').catch(error=>{disconnected();throw error;}).finally(()=>{stateRequest=null;});return stateRequest;}
async function withAction(fn){if(state.actionBusy)return;state.actionBusy=true;updateControls();try{return await fn();}finally{state.actionBusy=false;renderConnection();renderAccount();updateControls();}}
async function changeMonitor(enabled){return withAction(async()=>{controls.monitor.setValue(Boolean(state.model.MonitorRunning));await invoke(enabled?'StartMonitor':'StopMonitor');});}
async function runCheck(){return withAction(()=>invoke('CheckNow'));}
async function runDiagnostics(){if(state.diagnostic.Running)return;return withAction(()=>invoke('StartDiagnostics'));}
async function cancelDiagnostics(){return withAction(()=>invoke('CancelDiagnostics'));}

function showPage(page){if(page==='materials'||page==='original')page='overview';if(!pages.includes(page))return;state.page=page;for(const section of document.querySelectorAll('.page')){section.hidden=section.id!==`page-${page}`;delete section.dataset.enter;}$(`page-${page}`).dataset.enter='true';controls.navigation?.setValue(page);main.scrollTop=0;if(page==='account')renderAccount();if(page==='logs'&&state.started)void refreshLogs().catch(error=>toast(error.message));invalidate(650);}
document.querySelector('.brand').addEventListener('click',event=>{event.preventDefault();showPage('overview');});
controls.navigation=component('navigation','choices',{label:'界面导航',value:'overview',options:[{value:'overview',label:'连接'},{value:'account',label:'账号与设置'},{value:'diagnostics',label:'网络诊断'},{value:'logs',label:'运行日志'}],onChange:showPage});
controls.navigation.element.classList.add('nav-choices');for(const item of controls.navigation.element.querySelectorAll('button[data-choice]')){item.querySelector('svg')?.remove();item.prepend(icon(item.dataset.choice));}
controls.check=button('connection-actions','立即检查',()=>state.model.CredentialAvailable?runCheck():showPage('account'),'refresh');controls.check.element.classList.add('primary-action');
controls.monitor=component('monitor-control','switch',{label:'自动监测与重连',checked:false,onChange:action(changeMonitor)});
controls.monitor.element.setAttribute('aria-describedby','monitor-summary');
function age(value){const parsed=Date.parse(value||'');if(!Number.isFinite(parsed))return '—';const seconds=Math.max(0,Math.floor((Date.now()-parsed)/1000));return seconds<5?'刚刚':seconds<60?`${seconds} 秒前`:seconds<3600?`${Math.floor(seconds/60)} 分钟前`:`${Math.floor(seconds/3600)} 小时前`;}
function shortTime(value){const date=new Date(value||'');if(!Number.isFinite(date.getTime()))return '—';const pad=n=>String(n).padStart(2,'0');return `${pad(date.getMonth()+1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;}
function renderConnection(){
  const model=state.model,view=connectionView(model,state.connected),unconfigured=state.connected&&!model.CredentialAvailable;
  stage.dataset.state=view.tone;
  text('status-title',unconfigured?'尚未配置账号':view.title);text('status-detail',unconfigured?'填写校园网账号后，可开启自动监测与重连。':view.detail.split(/\r?\n/)[0]);$('status-detail').title=unconfigured?'':view.detail;
  text('connection-pill',{online:'已连接',offline:'未登录',connecting:'处理中',unknown:'未确认'}[view.tone]||'未确认');
  const source=model.Source==='probe'?'只读检查':model.Source==='monitor'?'后台监测':'尚未检查';
  text('connection-caption',`更新于 ${age(model.ObservedAt||model.UpdatedAt)} · ${source}${view.fresh?'':' · 认证状态未确认'}`);
  text('current-account',model.Account||'未配置');text('current-carrier',model.CredentialAvailable?(carriers[model.Carrier]||'未确认'):'未配置');text('last-login',shortTime(model.LastLoginAt));
  text('monitor-summary',!state.connected?'正在等待后台连接。':unconfigured?(model.MonitorRunning?'尚未配置账号，可先暂停监测。':'请先保存账号，再开启自动监测与重连。'):'开启后，检测到未登录会自动重新认证。');
  $('backend-indicator').hidden=state.connected;$('check-policy').hidden=Boolean(model.MonitorRunning)||unconfigured;
  if(controls.monitor.value!==Boolean(model.MonitorRunning))controls.monitor.setValue(Boolean(model.MonitorRunning));
  controls.check.label.textContent=unconfigured?'去填写账号':'立即检查';
}
function updateControls(){
  const ready=state.connected&&!state.actionBusy,model=state.model;
  controls.monitor.element.disabled=!ready||(!model.CredentialAvailable&&!model.MonitorRunning);
  controls.check.setDisabled(!ready||(Boolean(model.CredentialAvailable)&&state.diagnostic.Running));
  controls.diagnosticButton?.setDisabled(!ready||state.diagnostic.Running);if(controls.diagnosticButton)controls.diagnosticButton.element.hidden=Boolean(state.diagnostic.Running);
  if(controls.cancel){controls.cancel.element.hidden=!state.diagnostic.Running;controls.cancel.setDisabled(!ready);}
  for(const key of ['startup','launch'])if(controls[key])controls[key].element.disabled=!ready;
  controls.save?.setDisabled(!ready||!state.formDirty);controls.undo?.setDisabled(state.actionBusy);if(controls.undo)controls.undo.element.hidden=!state.formDirty;
  controls.forget?.setDisabled(!ready||!model.CredentialAvailable);controls.confirmForget?.setDisabled(!ready||!model.CredentialAvailable);
  controls.logRefresh?.setDisabled(!ready||state.logsBusy);
  for(const id of ['current-account-input','account-password-input'])if($(id))$(id).disabled=state.actionBusy;
  for(const b of controls.carrier?.element.querySelectorAll('button')||[])b.disabled=state.actionBusy;
}
function syncFormDirty(){state.formDirty=controls.account.value.trim()!==(state.model.Account||'')||controls.carrier.value!==(state.model.Carrier||'unicom')||controls.password.value!=='';updateControls();}
function accountInput(host,label,id,type='text'){const input=component(host,'search',{label,placeholder:type==='password'?'留空沿用原密码':'输入校园网账号',onChange:syncFormDirty}),element=input.element.querySelector('input');element.type=type;element.id=id;element.autocomplete=type==='password'?'new-password':'off';element.spellcheck=false;element.maxLength=type==='password'?256:128;if(type==='password')element.setAttribute('aria-describedby','password-help');element.addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.isComposing&&!controls.save.element.disabled){event.preventDefault();controls.save.element.click();}});return input;}
controls.account=accountInput('account-input','校园网账号','current-account-input');controls.password=accountInput('password-input','校园网密码','account-password-input','password');
controls.carrier=component('carrier-control','choices',{label:'运营商',value:'unicom',options:Object.entries(carriers).map(([value,label])=>({value,label})),onChange:syncFormDirty});
controls.startup=component('startup-control','switch',{label:'开机启动助手',checked:false,onChange:action(value=>setPreference('SetStartup',value))});
controls.launch=component('launch-control','switch',{label:'打开助手时自动监测',checked:false,onChange:action(value=>setPreference('SetLaunchPreference',value))});
controls.appearance=component('appearance-presets','choices',{label:'玻璃材质',value:state.appearance,options:appearancePresets,onChange:value=>setAppearance(value)});
controls.panelFill=component('panel-fill-control','switch',{label:'面板底色',checked:state.panelFill,onChange:value=>setPanelFill(value)});controls.panelFill.element.id='panel-fill-switch';
controls.scene=component('appearance-scenes','choices',{label:'玻璃背景',value:state.scene,options:scenePresets,onChange:value=>setScene(value)});
function setAppearance(value,{persist=true}={}){if(!appearancePresets.some(item=>item.value===value))return false;state.appearance=value;stage.dataset.appearance=value;controls.appearance.setValue(value);system?.setMaterial(resolveAppearanceMaterial(value));if(persist&&!saveAppearance(browserStorage(),value,appearanceKey))toast('风格已应用，本次未能记住选择。');invalidate(600);return true;}
function setPanelFill(enabled,{persist=true}={}){if(typeof enabled!=='boolean')return false;state.panelFill=enabled;stage.dataset.panelFill=enabled?'on':'off';controls.panelFill.setValue(enabled);if(persist&&!savePanelFill(browserStorage(),enabled,appearanceKey+'.panelFill'))toast('底色已应用，本次未能记住选择。');invalidate(600);return true;}
function setScene(value,{persist=true}={}){if(!scenePresets.some(item=>item.value===value))return false;state.scene=value;controls.scene.setValue(value);stage.dataset.scene=value;system?.setScene(value);if(persist&&!saveScene(browserStorage(),value,appearanceKey+'.scene'))toast('背景已应用，本次未能记住选择。');invalidate(600);return true;}
$('credential-icon').append(icon('shield'));
controls.save=button('account-actions','保存账号',saveAccount,'shield');controls.save.element.classList.add('primary-action');
controls.undo=button('account-actions','撤销修改',()=>{state.formDirty=false;controls.password.setValue('');renderAccount();updateControls();invalidate();});
controls.forget=button('account-forget','清除…',openForget);controls.forget.element.classList.add('danger-action');
button('forget-actions','保留账号',()=>$('forget-dialog').close());controls.confirmForget=button('forget-actions','确认清除',()=>{$('forget-dialog').close();return forgetAccount();});controls.confirmForget.element.classList.add('danger-action','danger-confirm');
function renderAccount(){const model=state.model;if(!state.formDirty){controls.account.setValue(model.Account||'');controls.carrier.setValue(model.Carrier||'unicom');}text('credential-state',model.CredentialAvailable?'已在本机加密保存':'尚未保存账号');controls.startup.setValue(Boolean(model.StartupEnabled));controls.launch.setValue(Boolean(model.MonitorOnLaunch));text('startup-copy',model.StartupEnabled?'已启用 · 登录 Windows 后驻留托盘':'未启用 · 登录 Windows 后不会自动打开');}
async function saveAccount(){return withAction(async()=>{try{await invoke('SaveCredential',{account:controls.account.value.trim(),carrier:controls.carrier.value,password:controls.password.value});state.formDirty=false;renderAccount();}finally{controls.password.setValue('');syncFormDirty();}});}
async function setPreference(command,enabled){return withAction(async()=>{try{return await invoke(command,{enabled:Boolean(enabled)});}finally{renderAccount();}});}
function openForget(){if(state.connected&&!state.actionBusy&&state.model.CredentialAvailable&&!$('forget-dialog').open)$('forget-dialog').showModal();}
async function forgetAccount(){return withAction(async()=>{await invoke('ForgetCredential',{confirmed:true});state.formDirty=false;controls.password.setValue('');renderAccount();});}

controls.diagnosticButton=button('diagnostic-actions','开始诊断',runDiagnostics,'diagnostics');controls.diagnosticButton.element.classList.add('primary-action');
controls.cancel=button('diagnostic-actions','结束检查',cancelDiagnostics);controls.cancel.element.hidden=true;
controls.progress=component('diagnostic-progress','progress',{label:'正在检查',value:0,max:100,completeLabel:'检查完成',completionColor:'green',motion:'system'});
const progressTrack=controls.progress.element.querySelector('[role=progressbar]');progressTrack.removeAttribute('aria-valuenow');progressTrack.setAttribute('aria-valuetext','正在检查，请稍候');
function renderDiagnostic(){
  const diagnostic=state.diagnostic,result=diagnostic.Result,presentation=result?diagnosticView(result,state.connected):null;
  $('diagnostic-progress').hidden=!diagnostic.Running;
  $('diagnostic-heading').dataset.tone=!diagnostic.Running&&presentation&&!presentation.historical&&presentation.completionColor==='green'?'success':'neutral';
  if(diagnostic.Running){text('diagnostic-heading','正在检查网络');text('diagnostic-copy','检查认证与端口状态，请稍候。不会提交登录。');if(controls.progress.value!==0)controls.progress.setValue(0,{animate:false});}
  else if(result){text('diagnostic-heading',presentation.title);text('diagnostic-copy',presentation.summary);}
  else{text('diagnostic-heading','尚未运行诊断');text('diagnostic-copy','检查认证与端口状态，不会提交登录。');}
  const stamp=diagnostic.Running?'running':result?result.CompletedAt+':'+presentation.historical:'idle';
  if(stamp!==lastDiagnostic){
    lastDiagnostic=stamp;
    const items=diagnostic.Running?[{Label:'正在检查认证与网络端口',Value:'等待结果',Tone:'Neutral'}]:presentation?.items||[{Label:'校园网认证与网络端口',Value:'尚未检查',Tone:'Neutral'}];
    $('diagnostic-steps').replaceChildren(...items.map(item=>{const row=document.createElement('li');row.className='diagnostic-step';row.dataset.state=item.Tone==='Success'?'done':item.Tone==='Warning'?'warning':'waiting';const marker=document.createElement('span'),label=document.createElement('strong'),value=document.createElement('span');marker.className='step-marker';marker.setAttribute('aria-hidden','true');marker.textContent=item.Tone==='Success'?'✓':item.Tone==='Warning'?'!':'○';label.textContent=item.Label;value.className='step-state';value.textContent=item.Value;row.append(marker,label,value);return row;}));
    const advice=diagnostic.Running?'':presentation?.advice||'';text('diagnostic-advice',advice);$('diagnostic-advice-block').hidden=!advice;$('diagnostic-advice-block').dataset.tone=presentation?.completionColor==='green'?'success':'warning';
    text('diagnostic-detail',result?.Text||'');$('diagnostic-details').hidden=!result||Boolean(diagnostic.Running);invalidate(650);
  }
}

controls.logSearch=component('log-search','search',{label:'搜索运行日志',placeholder:'搜索运行记录',onChange:value=>{state.search=value;renderLogs();}});
controls.logFilter=component('log-filter','choices',{label:'日志分类',value:'all',options:[{value:'all',label:'全部'},{value:'monitor',label:'监测'},{value:'warning',label:'异常'}],onChange:value=>{state.filter=value;renderLogs();}});
controls.logRefresh=button('log-refresh','刷新',refreshLogs,'refresh');
function refreshLogs(){if(logsRequest)return logsRequest;state.logsBusy=true;updateControls();logsRequest=invoke('GetLogs').then(data=>{state.logsLoaded=true;state.logs=String(data.Text||'').split(/\r?\n/).filter(line=>line.trim()&&!/^暂无/.test(line)).map((line,index)=>{const match=/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(.*)$/.exec(line);const value=match?match[2]:line;return {stamp:match?match[1]:'',text:value,warning:/失败|异常|超时|拒绝|无效|未登录|未能|受限/.test(value),monitor:/监测|登录|认证|重连|检查/.test(value),index};}).sort((a,b)=>b.stamp.localeCompare(a.stamp)||b.index-a.index).slice(0,100);renderLogs();}).finally(()=>{state.logsBusy=false;logsRequest=null;updateControls();});return logsRequest;}
function renderLogs(){
  const entries=state.logs.filter(item=>(state.filter==='all'||state.filter==='warning'&&item.warning||state.filter==='monitor'&&item.monitor)&&item.text.includes(state.search.trim()));
  $('log-list').replaceChildren(...entries.map(item=>{const row=document.createElement('div');row.className='log-row';row.dataset.level=item.warning?'notice':'normal';const time=document.createElement('time'),message=document.createElement('span'),marker=document.createElement('span');time.textContent=item.stamp?item.stamp.slice(5,10)+' '+item.stamp.slice(11):'—';if(item.stamp)time.dateTime=item.stamp.replace(' ','T');message.className='log-message';marker.className='log-marker';marker.setAttribute('role','img');marker.setAttribute('aria-label',item.warning?'异常记录':'运行记录');message.append(marker,document.createTextNode(item.text));row.append(time,message);return row;}));
  if(!entries.length){const empty=document.createElement('p');empty.id='log-empty';empty.className='log-empty';empty.textContent=state.logsLoaded?'没有匹配的运行记录。':'进入页面后读取运行日志。';$('log-list').append(empty);}invalidate();
}

system=createGlassSystem(stage,{material:resolveAppearanceMaterial(state.appearance),scene:state.scene,artwork:campusArtwork,motion:false,audio:{enabled:false,storage:null}});
// Closed details can retain client rects in WebView2; hide the lens explicitly.
$('diagnostic-details').addEventListener('toggle',()=>{$('diagnostic-detail').hidden=!$('diagnostic-details').open;invalidate(350);});
setAppearance(state.appearance,{persist:false});
setPanelFill(state.panelFill,{persist:false});
setScene(state.scene,{persist:false});
renderConnection();renderAccount();renderDiagnostic();renderLogs();updateControls();showPage('overview');
const polling=setInterval(()=>{if(state.started&&!document.hidden&&!state.actionBusy)void refreshState().catch(()=>{});},2000);
function expireViews(){renderConnection();if(state.diagnostic.Result)renderDiagnostic();}
const expiry=setInterval(expireViews,1000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden){expireViews();if(state.started)void refreshState().catch(()=>{});}});
function snapshot(){const view=connectionView(state.model,state.connected);return {connected:state.connected,auth:view.auth,modelAuth:state.model.AuthState||'Unknown',monitorState:state.model.MonitorState||'',observedAt:state.model.ObservedAt||'',expiresAt:state.model.ExpiresAt||'',updatedAt:state.model.UpdatedAt||'',sampledAt:new Date().toISOString(),monitorRunning:Boolean(state.model.MonitorRunning),readOnlySettings:Boolean(state.model.ReadOnlySettings),startupEnabled:Boolean(state.model.StartupEnabled),monitorOnLaunch:Boolean(state.model.MonitorOnLaunch),hasSavedAccount:Boolean(state.model.Account),credentialAvailable:Boolean(state.model.CredentialAvailable),source:state.model.Source||'none',diagnosticRunning:state.diagnostic.Running,diagnosticCompleted:Boolean(state.diagnostic.Result),diagnosticAuth:state.diagnostic.Result?.AuthState||'Unknown',logsLoaded:state.logsLoaded,logCount:state.logs.length,actionBusy:state.actionBusy,formDirty:state.formDirty,webgl:stage.classList.contains('webgl-ready'),page:state.page,viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},horizontalOverflow:main.scrollWidth>main.clientWidth+1,errors:[...errors]};}
window.LensApp={controls,system,invoke,refreshState,showPage,runCheck,runDiagnostics,changeMonitor,saveAccount,setPreference,openForget,refreshLogs,setAppearance,setPanelFill,setScene,snapshot,hostRequest,send};
window.addEventListener('pagehide',()=>{clearInterval(polling);clearInterval(expiry);clearTimeout(toastTimer);for(const item of pending.values())clearTimeout(item.timeout);for(const item of hostPending.values())clearTimeout(item.timeout);system.destroy();for(const handle of handles)handle.destroy();});
setTimeout(()=>send({type:'ready',dpr:devicePixelRatio,availableWidth:screen.availWidth,availableHeight:screen.availHeight,availableLeft:screen.availLeft,availableTop:screen.availTop}),250);
