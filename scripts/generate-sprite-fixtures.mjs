// Pure TypeScript oracle; run with the fixtures service, never edit copied TS.
import { readFile, writeFile } from "node:fs/promises";
import { PART_SLOTS, parseSkin, parseAppearance, packFrame, toRenderable, composeAppearance, coloursOf } from "../frontend/packages/sprite/src/index.ts";
const root = new URL("../", import.meta.url);
const seeds = JSON.parse(await readFile(new URL("seed/skins.json", root), "utf8"));
const valid = () => ({ formatVersion: 1, name: "fixture", palette: [{id:"skin",hex:"#abcdef"},{id:"hair",hex:"#123456"}], parts: PART_SLOTS.map(slot => ({slot,frames:[{durationMs:120,cells: slot === "body" ? [[1,16],[0,240]] : [[0,256]]}]})) });
const skinCases = [];
const skinCase = (label, input) => skinCases.push({label,input,result:parseSkin(input)});
const patch = (label, changes) => skinCase(label, {...valid(), ...changes});
const frame = (label, changes) => { const input = valid(); Object.assign(input.parts[0].frames[0], changes); skinCase(label,input); };
for (const input of [null, false, 7, [], {}, "x"]) skinCase(`root ${JSON.stringify(input)}`, input);
for (const name of ["", 7, "a".repeat(65), "😀".repeat(33), "😀".repeat(32), "  name  ", "\uFEFF name \u00a0", "\b\f\u0000"]) patch(`name ${Array.from(JSON.stringify(name)).slice(0,30).join("")}`,{name});
for (const version of [null, 0, 2, "1"]) patch(`version ${version}`,{formatVersion:version});
patch("unknown fields and reversed slots",{junk:"<script>",parts:valid().parts.reverse(),palette:[{id:"skin",hex:"#abcdef",onload:"x"},{id:"hair",hex:"#123456"}]});
for (const palette of [null,{},[],[null],[{}],[{id:2,hex:"#123456"}],Array.from({length:33},(_,i)=>({id:`c${i}`,hex:"#123456"}))]) patch("palette shape/count",{palette});
for (const id of ["", "Hair", "a b", "a;b:c", "x_1", "h".repeat(33), "constructor", "a-0"]) patch(`palette id ${id}`,{palette:[{id,hex:"#123456"}]});
for (const hex of [null,3,"red","#fff","#12345g","url(#x)","#ABCDEF"]) patch(`hex ${hex}`,{palette:[{id:"skin",hex}]});
patch("duplicate precedes bad hex",{palette:[{id:"skin",hex:"#123456"},{id:"skin",hex:"red"}]});
for (const parts of [null,{},[],valid().parts.slice(0,4),[...valid().parts,valid().parts[0]], [null], [{slot:"hat",frames:[]}], [{slot:"body",frames:[]}], [valid().parts[0],valid().parts[0],...valid().parts.slice(2)]]) patch("parts shape/count/order",{parts});
for (const durationMs of [null,"120",0,-1,0.5,10001,1,10000]) frame(`duration ${durationMs}`,{durationMs});
for (const cells of [null,{},[],[1],[[0,1,2]],[[-1,256]],[[0.5,256]],[[9,256]],[[9,0]],[[0,0]],[[0,-1]],[[0,0.5]],[[0,"256"]],[[0,255]],[[0,257]],[[0,1e20]],[[1,128],[1,128]],[[2,256]]]) frame(`cells ${JSON.stringify(cells)}`,{cells});
const manyFrames=valid(); manyFrames.parts[0].frames=Array(9).fill(manyFrames.parts[0].frames[0]); skinCase("too many frames",manyFrames);
patch("canonical size first even before shape",{formatVersion:2,pad:Array(4000).fill(1e20)});
for (const seed of seeds) skinCase(seed.id,seed.source);

const appearanceCases=[];
const look=()=>({skinId:"worn",parts:{},colours:[]});
const appearanceCase=(label,input)=>appearanceCases.push({label,input,result:parseAppearance(input)});
for(const input of [null,[],{},look(),{...look(),parts:{hair:"worn",shirt:"other"},junk:1}]) appearanceCase("recipe shape/normalization",input);
for(const skinId of [null,"",7,"x".repeat(65),"😀".repeat(33),"😀".repeat(32)]) appearanceCase("skin ID",{...look(),skinId});
for(const parts of [null,[],{hat:"x"},{hair:null},{hair:7},{hair:""},{hair:"x".repeat(65)},{hair:"other",shirt:"third"}]) appearanceCase("parts",{...look(),parts});
for(const colours of [null,{},[null],[{}],[{id:3,hex:"#123456"}],[{id:"hair",hex:null}],[{id:"hair",hex:"red"}],[{id:"Hair",hex:"#123456"}],[{id:"constructor",hex:"#123456"}],[{id:"hair",hex:"#123456"},{id:"hair",hex:"bad"}],Array.from({length:33},(_,i)=>({id:`c${i}`,hex:"#123456"}))]) appearanceCase("colours",{...look(),colours});

let state=14251;
const next=()=>{state=(Math.imul(state,1664525)+1013904223)>>>0;return state;};
const drawings=[];
for(let n=0;n<32;n++) {
  const input=valid();
  for(let p=0;p<5;p++) input.parts[p].frames=Array.from({length:1+n%3},(_,f)=>packFrame(Array.from({length:256},(_,i)=>n===0?0:n===1?1:n===2?(i%16<8?1:2):next()%3),1+f*120));
  drawings.push({source:input,renderable:toRenderable(input)});
}
const compositions=[];
const skins={a:drawings[3].renderable,b:drawings[4].renderable,blank:drawings[0].renderable};
for(const skinId of ["a","missing"]) for(const parts of [{},{hair:"b"},{body:"missing"},{hair:"blank"},Object.fromEntries(PART_SLOTS.map(s=>[s,"b"])),{body:"b",pants:"b",hair:"a"}]) {
  const appearance={skinId,parts,colours:[]};
  const result=composeAppearance(appearance,new Map(Object.entries(skins)));
  compositions.push({appearance,skins,result:result??null,colours:result?coloursOf(result):[]});
}
const numbers=[0,-0,1,1e20,1e21,1e23,1e-6,1e-7,0.0015,Number.MIN_VALUE,Number.MAX_VALUE,9007199254740993,1000000000000000100];
for(let n=0;n<200;n++) {const buffer=new ArrayBuffer(8),v=new DataView(buffer);v.setUint32(0,next());v.setUint32(4,next());const x=v.getFloat64(0);if(Number.isFinite(x))numbers.push(x);}
const sizes=[...numbers.map(n=>({raw:String(n),expected:JSON.stringify(n).length})),...['"\\b\\f\\u0000"','{"😀":"日本語","a":[1e20,0.0015]}','1e400'].map(raw=>({raw,expected:Buffer.byteLength(JSON.stringify(JSON.parse(raw)))}))];
const output={skinCases,appearanceCases,drawings,compositions,sizes};
await writeFile(new URL("test/fixtures/sprite.json",root),JSON.stringify(output)+"\n");
console.log(Object.fromEntries(Object.entries(output).map(([k,v])=>[k,v.length])));
