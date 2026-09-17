import matter from 'gray-matter';
import YAML from 'yaml';
export function decode(text:string) {
  if(!text.startsWith('---\n')&&!text.startsWith('---\r\n'))throw new Error('缺少 YAML frontmatter');
  return matter(text,{engines:{yaml:(source:string)=>{const document=YAML.parseDocument(source,{uniqueKeys:true});if(document.errors.length)throw new Error(document.errors.map(e=>e.message).join('; '));return document.toJS();}}});
}
export function encode(meta:object,body:string) {return `---\n${YAML.stringify(meta,{lineWidth:0})}---\n${body.startsWith('\n')?'':'\n'}${body}`;}
