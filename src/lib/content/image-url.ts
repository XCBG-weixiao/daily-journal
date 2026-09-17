export function imageUrl(src:string|undefined){
  if(!src)return null;
  const match=src.match(/^\.\.\/assets\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/([a-zA-Z0-9._-]+)$/i);
  return match?`/api/assets/${match[1]}/${match[2]}`:null;
}
export function firstImage(body:string){return /!\[[^\]]*\]\(([^\s)]+)\)/.exec(body)?.[1];}
