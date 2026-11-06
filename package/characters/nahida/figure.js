const SVGNS='http://www.w3.org/2000/svg';
const STATES=Object.freeze(['neutral','happy','wink','sit','sleep','dragged']);
const ALIAS=Object.freeze({stand:'neutral',idle:'neutral',wave:'happy',nod:'happy',drag:'dragged',held:'dragged',sleeping:'sleep'});
function stateOf(v){const x=String(v||'neutral').toLowerCase();const y=ALIAS[x]||x;return STATES.includes(y)?y:'neutral';}
function loadImage(src){return new Promise((ok,bad)=>{const im=new Image();im.onload=()=>ok(im);im.onerror=()=>bad(new Error('Nahida asset load failed: '+src));im.src=String(src);});}
function u(base,path){return new URL(path,base instanceof URL?base:new URL(String(base),import.meta.url));}
export async function createNahidaFigure(base=new URL('./',import.meta.url),opts={}){
 const root=base instanceof URL?base:new URL(String(base),import.meta.url),asset=opts.asset||(p=>u(root,p));
 const localRoot=/\/characters\/nahida\/$/.test(root.pathname)||/\/nahida\/$/.test(root.pathname),prefix=localRoot?'':'characters/nahida/';
 let outfit='original',state=stateOf(opts.state||opts.pose),cache=new Map();
 const model=opts.model||await (async()=>{try{return await (await fetch(asset(prefix+'model.json'))).json()}catch(_){return {character:'nahida'}}})();
 const src=s=>asset(prefix+'outfits/'+outfit+'/states/'+s+'.png');
 const load=s=>{if(!cache.has(s))cache.set(s,loadImage(src(s)));return cache.get(s)};
 await load(state);
 function draw(target,face={},frame={}){if(!target||!target.appendChild)return;state=stateOf(frame.state||frame.pose||frame.action||face.state||face.pose||state);const href=src(state);target.replaceChildren();const im=document.createElementNS(SVGNS,'image');[['x','0'],['y','0'],['width','280'],['height','280'],['preserveAspectRatio','xMidYMid meet']].forEach(([k,v])=>im.setAttribute(k,v));im.setAttribute('href',String(href));im.setAttributeNS('http://www.w3.org/1999/xlink','xlink:href',String(href));im.setAttribute('data-character','nahida');im.setAttribute('data-outfit',outfit);im.setAttribute('data-state',state);target.appendChild(im)}
 function setScheme(id,o={}){outfit='original';state=stateOf(o.state||state);return outfit}
 return {draw,gestures:['nod','wave','shake','bow'],setScheme,preload:()=>Promise.all(STATES.map(load)),dispose:()=>cache.clear(),reset:()=>{state='neutral'},snapshot:()=>({character:'nahida',outfit,state}),painted:Promise.resolve(),get scheme(){return 'nahida-original'},get colors(){return {z:'#7AA96F'}},get outfit(){return outfit},get state(){return state},anchors:{gaze:[144,92],tear:[142,112],tears:[[136,112],[158,112]],z:[210,48],hearts:[94,176,68],bubble:[140,24]},model};
}
export async function createNahidaBody(base,opts={}){const figure=await createNahidaFigure(base,opts);if(opts.kit&&typeof opts.kit.createBody==='function')return opts.kit.createBody(opts.host,{figure});return {status:'ready',character:'nahida',outfit:'original',figure,experimental:true}}
export const createCharacterBody=createNahidaBody;
export const createWhaleBody=createNahidaBody;
if(typeof module!=='undefined'&&module.exports)module.exports={createNahidaFigure,createNahidaBody,createCharacterBody,createWhaleBody};
