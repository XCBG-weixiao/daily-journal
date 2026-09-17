import {z} from 'zod';
import {localDate,validDate} from './dates';
export const metricKeys=['duration_min','distance_km','pages'] as const;
export type MetricKey=typeof metricKeys[number];
export const metricNames:Record<MetricKey,string>={duration_min:'时长',distance_km:'距离',pages:'页数'};
export const metricUnits:Record<MetricKey,string>={duration_min:'min',distance_km:'km',pages:'页'};
export const settingsSchema=z.object({schema_version:z.literal(1),timezone:z.literal('Asia/Shanghai'),week_starts_on:z.literal(1)}).strict();
export const activitySchema=z.object({schema_version:z.literal(1),id:z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),name:z.string().trim().min(1),icon:z.string().min(1),color:z.string().regex(/^#[0-9a-fA-F]{6}$/),metrics:z.array(z.enum(metricKeys)).refine(a=>new Set(a).size===a.length,'指标不能重复')}).strict();
export type Activity=z.infer<typeof activitySchema> & {body:string};
export const entrySchema=z.object({schema_version:z.literal(1),id:z.uuid(),kind:z.enum(['event','journal']),title:z.string().trim().min(1,'请输入标题'),date:z.string().refine(validDate,'日期无效'),started_at:z.iso.datetime({offset:true}).optional(),activity_id:z.string().optional(),metrics:z.object({duration_min:z.number().nonnegative().optional(),distance_km:z.number().nonnegative().optional(),pages:z.number().int().nonnegative().optional()}).strict().optional(),tags:z.array(z.string().trim().min(1)).transform(v=>[...new Set(v)]).optional(),cover:z.string().optional()}).strict();
export type EntryMeta=z.infer<typeof entrySchema>;
export type Entry=EntryMeta & {body:string;hash:string};
export type Issue={file:string;message:string};
export type Snapshot={activities:Activity[];entries:Entry[];issues:Issue[];demo:boolean};
export function parseMeta(input:unknown,activities:Activity[],now=new Date()):EntryMeta {
  const m=entrySchema.parse(input);
  if(m.date>localDate(now)) throw new Error('date：不能记录未来日期');
  if(m.started_at && (new Date(m.started_at)>now || localDate(new Date(m.started_at))!==m.date)) throw new Error('started_at：时间不能在未来，且按上海时区换算后的日期须与 date 一致');
  if(m.kind==='journal' && (m.activity_id!==undefined || m.metrics!==undefined)) throw new Error('journal：不允许 activity_id 或 metrics');
  if(m.kind==='event') {
    const a=activities.find(a=>a.id===m.activity_id);
    if(!a) throw new Error('activity_id：必须引用已有活动');
    for(const key of Object.keys(m.metrics??{})) if(!a.metrics.includes(key as MetricKey)) throw new Error(`metrics.${key}：该活动不支持此指标`);
  }
  if(m.cover && !/^\.\.\/assets\/[0-9a-f-]+\/[a-zA-Z0-9._-]+$/.test(m.cover)) throw new Error('cover：应为 ../assets/<UUID>/<filename>');
  return m;
}
