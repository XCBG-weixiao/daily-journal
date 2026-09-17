import 'server-only';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {z} from 'zod';
import {activitySchema,Entry,parseMeta,settingsSchema,Snapshot} from './schema';
import {decode,encode} from './markdown';
export const rootDir=()=>path.resolve(/* turbopackIgnore: true */ process.env.CONTENT_DIR??'./content');
export const hash=(text:string)=>createHash('sha256').update(text).digest('hex');
export function within(parent:string,child:string){const rel=path.relative(parent,child);return rel!==''&&!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel);}
export async function safePath(relative:string){const root=await fs.realpath(/* turbopackIgnore: true */ rootDir());const target=await fs.realpath(path.resolve(root,relative));if(!within(root,target))throw new Error('路径超出内容目录');return target;}
export const message=(error:unknown)=>error instanceof Error?error.message:String(error);
export async function snapshot(now=new Date()):Promise<Snapshot>{
  let config:string;
  try{config=await fs.readFile(await safePath('settings.json'),'utf8');}catch{throw new Error('无法读取 content/settings.json。请运行 npm run content:init，并检查 CONTENT_DIR 和访问权限。');}
  settingsSchema.parse(JSON.parse(config));
  const result:Snapshot={entries:[],activities:[],issues:[],demo:false};
  for(const area of ['activities','entries'] as const){
    const dir=await safePath(area);const names=(await fs.readdir(dir)).filter(n=>n.endsWith('.md')).sort();
    const ids=new Set<string>();
    for(const name of names){const file=`${area}/${name}`;try{
      const text=await fs.readFile(await safePath(file),'utf8'), parsed=decode(text);
      if(area==='activities'){const a=activitySchema.parse(parsed.data);if(ids.has(a.id))throw new Error('重复活动 ID');ids.add(a.id);if(name!==a.id+'.md')throw new Error('文件名必须与 id 一致');result.activities.push({...a,body:parsed.content});}
      else {const m=parseMeta(parsed.data,result.activities,now);if(ids.has(m.id))throw new Error('重复记录 ID');ids.add(m.id);if(name!==m.id+'.md')throw new Error('文件名必须与 id 一致');result.entries.push({...m,body:parsed.content,hash:hash(text)});}
    }catch(e){result.issues.push({file,message:message(e)});}}
  }
  result.demo=result.entries.some(e=>e.tags?.includes('示例'));
  return result;
}
const globalLocks=globalThis as typeof globalThis & {journalLocks?:Map<string,Promise<void>>};
const locks=globalLocks.journalLocks??=new Map<string,Promise<void>>();
export class ConflictError extends Error {}
export async function saveEntry(input:unknown,body:string,expectedHash:string|null,now=new Date()):Promise<Entry>{
  const id=z.object({id:z.uuid()}).parse(input).id;
  const previous=locks.get(id)??Promise.resolve();let release!:()=>void;
  const current=new Promise<void>(resolve=>{release=resolve});locks.set(id,current);await previous;
  try{
    const data=await snapshot(now),meta=parseMeta(input,data.activities,now),dir=await safePath('entries'),file=path.join(dir,id+'.md');
    let original:string|null=null;
    try{original=await fs.readFile(await safePath(`entries/${id}.md`),'utf8');}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}
    if(expectedHash===null?original!==null:original===null||hash(original)!==expectedHash)throw new ConflictError('文件已被修改或已存在。请保留当前草稿，重新打开记录后合并修改。');
    const text=encode(meta,body),temp=path.join(dir,`.${id}.${randomUUID()}.tmp`);
    await fs.writeFile(temp,text,{flag:'wx'});
    try{if(expectedHash===null){await fs.link(temp,file);await fs.unlink(temp);}else await fs.rename(temp,file);}catch(e){await fs.unlink(temp);throw e;}
    return {...meta,body,hash:hash(text)};
  }finally{release();if(locks.get(id)===current)locks.delete(id);}
}
