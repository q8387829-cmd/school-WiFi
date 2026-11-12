export const appearanceStorageKey='campus.lens.appearance.v1';
export const appearancePresets=Object.freeze([
  Object.freeze({value:'thick',label:'厚润'}),
  Object.freeze({value:'clear',label:'通透'}),
  Object.freeze({value:'soft',label:'柔和'}),
]);
export const scenePresets=Object.freeze([
  Object.freeze({value:'aurora',label:'流光'}),
  Object.freeze({value:'grid',label:'纸面网格'}),
  Object.freeze({value:'ocean',label:'深海'}),
]);
const known=value=>appearancePresets.some(preset=>preset.value===value);
export function loadAppearance(storage,key=appearanceStorageKey){try{const value=storage?.getItem(key);return known(value)?value:'thick';}catch{return 'thick';}}
export function saveAppearance(storage,value,key=appearanceStorageKey){if(!known(value)||!storage)return false;try{if(storage.getItem?.(key)==='preview'&&!['true','false'].includes(storage.getItem?.(key+'.panelFill')))storage.setItem(key+'.panelFill','false');storage.setItem(key,value);return true;}catch{return false;}}
export function resolveAppearanceMaterial(value){return known(value)?value:'thick';}
export function loadPanelFill(storage,key=appearanceStorageKey+'.panelFill',legacyKey=appearanceStorageKey){try{const value=storage?.getItem(key);if(value==='true'||value==='false')return value==='true';return storage?.getItem(legacyKey)!=='preview';}catch{return true;}}
export function savePanelFill(storage,enabled,key=appearanceStorageKey+'.panelFill'){if(!storage||typeof enabled!=='boolean')return false;try{storage.setItem(key,String(enabled));return true;}catch{return false;}}
export function loadScene(storage,key=appearanceStorageKey+'.scene'){try{const value=storage?.getItem(key);return scenePresets.some(item=>item.value===value)?value:'aurora';}catch{return 'aurora';}}
export function saveScene(storage,value,key=appearanceStorageKey+'.scene'){if(!storage||!scenePresets.some(item=>item.value===value))return false;try{storage.setItem(key,value);return true;}catch{return false;}}
