export const TIMEZONE = 'Asia/Shanghai';
export function localDate(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {timeZone: TIMEZONE, year:'numeric', month:'2-digit', day:'2-digit'}).format(now);
}
export function validDate(value:string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(value + 'T00:00:00Z');
  return Number.isFinite(d.getTime()) && d.toISOString().slice(0,10) === value;
}
export function shiftDay(value:string, amount:number) {
  const d = new Date(value+'T00:00:00Z'); d.setUTCDate(d.getUTCDate()+amount);
  return d.toISOString().slice(0,10);
}
export function shiftMonth(value:string, amount:number) {
  const d = new Date(value+'-01T00:00:00Z'); d.setUTCMonth(d.getUTCMonth()+amount);
  return d.toISOString().slice(0,7);
}
export function weekday(value:string) {return (new Date(value+'T00:00:00Z').getUTCDay()+6)%7;}
export function monthDays(month:string) {
  const first=month+'-01', start=shiftDay(first,-weekday(first));
  return Array.from({length:42},(_,i)=>shiftDay(start,i));
}
export function yearDays(year:number): (string|null)[] {
  const first=`${year}-01-01`, end=`${year+1}-01-01`;
  const count=(Date.parse(end)-Date.parse(first))/86400000;
  const before=weekday(first), length=Math.ceil((before+count)/7)*7;
  return Array.from({length},(_,i)=>i<before||i>=before+count?null:shiftDay(first,i-before));
}
export function timeLabel(value?:string) {
  return value ? new Intl.DateTimeFormat('zh-CN',{timeZone:TIMEZONE,hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(value)) : '未设时间';
}
export function dayLabel(value:string) {return new Intl.DateTimeFormat('zh-CN',{timeZone:'UTC',month:'long',day:'numeric',weekday:'long'}).format(new Date(value+'T00:00:00Z'));}
export function getDate(value:string|undefined, defaultValue:string) {return value && validDate(value)?value:defaultValue;}
export function getMonth(value:string|undefined, defaultValue:string) {return value && validDate(value+'-01')?value:defaultValue;}
export function getYear(value:string|undefined, defaultValue:number) {return value && /^\d{4}$/.test(value) && +value>=1900 && +value<=9998?+value:defaultValue;}
