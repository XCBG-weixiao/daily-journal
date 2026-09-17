import 'server-only';
import fs from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import sharp from 'sharp';
import {z} from 'zod';
import {safePath,within} from './repository';
export const formats={jpeg:{ext:'jpg',type:'image/jpeg'},png:{ext:'png',type:'image/png'},webp:{ext:'webp',type:'image/webp'}};
export async function readAsset(id:string,name:string){
  z.uuid().parse(id);if(!/^[a-zA-Z0-9._-]+$/.test(name))throw new Error('无效图片文件名');
  const assets=await safePath('assets'),target=await safePath(`assets/${id}/${name}`);
  if(!within(assets,target))throw new Error('图片路径越界');
  const buffer=await fs.readFile(target),meta=await sharp(buffer).metadata();
  const format=formats[meta.format as keyof typeof formats];if(!format)throw new Error('不支持此图片类型');
  return {buffer,type:format.type};
}
export async function uploadAsset(id:string,buffer:Buffer){
  z.uuid().parse(id);if(buffer.length>10*1024*1024)throw new Error('图片超过 10 MB');
  const image=sharp(buffer,{limitInputPixels:40_000_000}),meta=await image.metadata();
  const format=formats[meta.format as keyof typeof formats];if(!format)throw new Error('仅支持 JPG、PNG、WebP');
  await image.stats();
  const assets=await safePath('assets');await fs.mkdir(path.join(assets,id),{recursive:true});
  const dir=await safePath(`assets/${id}`);if(!within(assets,dir))throw new Error('图片路径越界');
  const name=randomUUID()+'.'+format.ext;await fs.writeFile(path.join(/* turbopackIgnore: true */ dir,name),buffer,{flag:'wx'});
  return {path:`../assets/${id}/${name}`,url:`/api/assets/${id}/${name}`};
}
