import {Entry,metricKeys,MetricKey} from './schema';
export function ordered(entries:Entry[]) {return [...entries].sort((a,b)=>a.date.localeCompare(b.date)||(a.started_at?Date.parse(a.started_at):Infinity)-(b.started_at?Date.parse(b.started_at):Infinity)||a.id.localeCompare(b.id));}
export function summarize(entries:Entry[]) {
  const events=entries.filter(e=>e.kind==='event');
  const sums={} as Record<MetricKey,number|null>;
  const samples={} as Record<MetricKey,number>;
  for(const key of metricKeys){const values=events.flatMap(e=>e.metrics?.[key]===undefined?[]:[e.metrics[key]!]); samples[key]=values.length;sums[key]=values.length?Math.round(values.reduce((s,v)=>s+v,0)*100)/100:null;}
  return {count:events.length,days:new Set(events.map(e=>e.date)).size,sums,samples,averageDuration:samples.duration_min?Math.round(sums.duration_min!/samples.duration_min*10)/10:null};
}
