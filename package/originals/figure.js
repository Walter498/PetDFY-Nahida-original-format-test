const SVGNS = 'http://www.w3.org/2000/svg';
const STATES = Object.freeze(['neutral','happy','wink','sit','sleep','dragged']);
const OUTFITS = Object.freeze(['original','pajamas','sailor','blazer']);
const ALIAS = Object.freeze({stand:'neutral',idle:'neutral',wave:'happy',nod:'happy',drag:'dragged',held:'dragged',sleeping:'sleep'});
function canonicalState(value){const x=String(value||'neutral').toLowerCase();const y=ALIAS[x]||x;return STATES.includes(y)?y:'neutral';}
function canonicalOutfit(value){const x=String(value||'original').toLowerCase();return OUTFITS.includes(x)?x:'original';}
function url(base,path){return new URL(path,base instanceof URL?base:new URL(String(base),import.meta.url));}
function loadImage(src){return new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>resolve(im);im.onerror=()=>reject(new Error('Nahida asset load failed: '+src));im.src=String(src);});}

export async function createNahidaFigure(base=new URL('./',import.meta.url),opts={}){
  const root=base instanceof URL?base:new URL(String(base),import.meta.url);
  const asset=opts.asset||(p=>url(root,p));
  let outfit=canonicalOutfit(opts.outfit||opts.scheme);
  let state=canonicalState(opts.state||opts.pose);
  const cache=new Map();
  const model=opts.model||await (async()=>{try{return await (await fetch(url(root,'model.json'))).json();}catch(_){return {character:'nahida',runtimeMode:'state-sprite'};}})();
  const path=(of,st)=>asset((of==='original'?'states/':'outfits/'+of+'/states/')+st+'.png');
  const load=(of,st)=>{const k=of+'/'+st;if(!cache.has(k))cache.set(k,loadImage(path(of,st)));return cache.get(k);};
  await load(outfit,state);
  function pick(face,frame){const f=frame||{},c=face||{};return canonicalState(f.state||f.pose||f.action||c.state||c.pose||c.action||state);}
  function draw(target,face={},frame={}){
    if(!target||typeof target.appendChild!=='function')return;
    state=pick(face,frame);const src=path(outfit,state);target.replaceChildren();
    const im=document.createElementNS(SVGNS,'image');
    for(const [k,v] of [['x','0'],['y','0'],['width','280'],['height','280'],['preserveAspectRatio','xMidYMid meet']])im.setAttribute(k,v);
    im.setAttribute('href',String(src));im.setAttributeNS('http://www.w3.org/1999/xlink','xlink:href',String(src));
    im.setAttribute('data-character','nahida');im.setAttribute('data-outfit',outfit);im.setAttribute('data-state',state);target.appendChild(im);
  }
  function setScheme(id,o={}){outfit=canonicalOutfit(o.outfit||id);state=canonicalState(o.state||state);return outfit;}
  return {draw,gestures:['nod','wave','shake','bow'],setScheme,preload:()=>Promise.all(STATES.map(s=>load(outfit,s))),dispose:()=>cache.clear(),reset:()=>{state='neutral'},snapshot:()=>`<image href="${String(path(outfit,state))}" x="0" y="0" width="280" height="280"/>`,painted:Promise.resolve(),get scheme(){return 'nahida-'+outfit},get colors(){return {z:'#7AA96F'}},get outfit(){return outfit},get state(){return state},schemes:[{id:'nahida',outfits:OUTFITS}],anchors:{gaze:[144,92],tear:[142,112],tears:[[136,112],[158,112]],z:[210,48],hearts:[94,176,68],bubble:[140,24]},model};
}
export async function createNahidaBody(base,opts={}){const figure=await createNahidaFigure(base,opts);if(opts.kit&&typeof opts.kit.createBody==='function')return opts.kit.createBody(opts.host,{figure});return {status:'ready',character:'nahida',outfit:figure.outfit,figure,experimental:true};}
export const createWhaleBody=createNahidaBody;
if(typeof module!=='undefined'&&module.exports)module.exports={createNahidaFigure,createNahidaBody,createWhaleBody};
