import Link from "next/link";
import {
  ArrowLeft,
  ArrowRight,
  Plus,
  ArrowUpRight,
  FileText,
} from "lucide-react";
import type { CSSProperties, ReactNode } from "react";
import {
  Activity,
  Entry,
  metricNames,
  metricUnits,
} from "@/lib/content/schema";
import {
  dayLabel,
  localDate,
  monthDays,
  shiftMonth,
  timeLabel,
  yearDays,
} from "@/lib/content/dates";
import { ordered, summarize } from "@/lib/content/aggregate";
import { firstImage } from "@/lib/content/image-url";
import { LocalImage } from "./markdown";
export const tone = (color: string) =>
  ({ "--activity": color }) as CSSProperties;
export function PageHeader({
  eyebrow,
  title,
  description,
  children,
}: {
  eyebrow: string;
  title: string;
  description?: string;
  children?: ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        {description && <p className="subtitle">{description}</p>}
      </div>
      <div className="header-actions">{children}</div>
    </header>
  );
}
export function AddLink({
  date,
  activity,
}: {
  date?: string;
  activity?: string;
}) {
  return (
    <Link
      className="button primary"
      href={`/entries/new?date=${date ?? localDate()}${activity ? "&activity=" + activity : ""}`}
    >
      <Plus size={16} />
      记录一下
    </Link>
  );
}
export function Period({
  month,
  base = "/calendar",
}: {
  month: string;
  base?: string;
}) {
  const separator = base.includes("?") ? "&" : "?";
  return (
    <div className="period">
      <Link
        className="icon-button"
        aria-label="上个月"
        href={`${base}${separator}month=${shiftMonth(month, -1)}&year=${shiftMonth(month, -1).slice(0, 4)}`}
      >
        <ArrowLeft size={16} />
      </Link>
      <span>
        {month.slice(0, 4)} 年 {Number(month.slice(5))} 月
      </span>
      <Link
        className="icon-button"
        aria-label="下个月"
        href={`${base}${separator}month=${shiftMonth(month, 1)}&year=${shiftMonth(month, 1).slice(0, 4)}`}
      >
        <ArrowRight size={16} />
      </Link>
    </div>
  );
}
export function YearNav({
  year,
  base = "/activities",
  month,
}: {
  year: number;
  base?: string;
  month?: string;
}) {
  return (
    <div className="period">
      <Link
        className="icon-button"
        aria-label="上一年"
        href={`${base}?year=${year - 1}${month ? "&month=" + `${year - 1}-${month.slice(5)}` : ""}`}
      >
        <ArrowLeft size={16} />
      </Link>
      <span>{year} 年</span>
      <Link
        className="icon-button"
        aria-label="下一年"
        href={`${base}?year=${year + 1}${month ? "&month=" + `${year + 1}-${month.slice(5)}` : ""}`}
      >
        <ArrowRight size={16} />
      </Link>
    </div>
  );
}
export function Legend({ activities }: { activities: Activity[] }) {
  return (
    <div className="legend">
      {activities.map((a) => (
        <span key={a.id} style={tone(a.color)}>
          <i className="dot" />
          {a.name}
        </span>
      ))}
      <span>
        <FileText size={12} />
        日记
      </span>
    </div>
  );
}
export function Calendar({
  month,
  date,
  entries,
  activities,
  base = "/calendar",
}: {
  month: string;
  date?: string;
  entries: Entry[];
  activities: Activity[];
  base?: string;
}) {
  const today = localDate();
  return (
    <>
      <div className="weekdays">
        {["一", "二", "三", "四", "五", "六", "日"].map((d) => (
          <span key={d}>{d}</span>
        ))}
      </div>
      <div className="month-grid">
        {monthDays(month).map((day) => {
          const es = entries.filter((e) => e.date === day),
            as = activities.filter((a) =>
              es.some((e) => e.activity_id === a.id),
            ),
            journal = es.some((e) => e.kind === "journal"),
            content = (
              <>
                <span className="day-number">{Number(day.slice(8))}</span>
                <span className="day-markers">
                  {as.slice(0, 3).map((a) => (
                    <i className="dot" key={a.id} style={tone(a.color)} />
                  ))}
                  {journal && <FileText size={11} />}
                </span>
                {as.length > 3 && <small>+{as.length - 3} 种</small>}
                {es.length > 0 && (
                  <span className="day-count">{es.length} 条记录</span>
                )}
              </>
            );
          const cls = `day ${day === date ? "selected" : ""} ${day === today ? "today" : ""} ${day.slice(0, 7) !== month ? "adjacent" : ""}`;
          return day > today ? (
            <div
              key={day}
              className={cls + " future"}
              aria-label={`${day}，未来日期`}
            >
              {content}
            </div>
          ) : (
            <Link
              className={cls}
              aria-label={`${day}，${es.length} 条记录`}
              aria-current={day === date ? "date" : undefined}
              key={day}
              href={`${base}?month=${day.slice(0, 7)}&year=${day.slice(0, 4)}&date=${day}`}
            >
              {content}
            </Link>
          );
        })}
      </div>
    </>
  );
}
export function EntryCard({
  entry,
  activity,
  compact = false,
}: {
  entry: Entry;
  activity?: Activity;
  compact?: boolean;
}) {
  const image = entry.cover ?? firstImage(entry.body);
  const excerpt = entry.body
    .replace(/!\[[^\]]*\]\([^)]+\)/g, "")
    .replace(/[#>*`\[\]]/g, "")
    .trim()
    .slice(0, compact ? 85 : 210);
  return (
    <article
      className={`entry-card ${compact ? "small" : ""}`}
      style={tone(activity?.color ?? "#738094")}
    >
      <div className="entry-meta">
        <span>{timeLabel(entry.started_at)}</span>
        {activity ? (
          <Link
            href={`/activities/${activity.id}?year=${entry.date.slice(0, 4)}&month=${entry.date.slice(0, 7)}&date=${entry.date}`}
            className="activity-label"
          >
            <i className="dot" />
            {activity.name}
          </Link>
        ) : (
          <span>日记</span>
        )}
      </div>
      <Link href={`/entries/${entry.id}`} className="entry-title">
        {entry.title}
        <ArrowUpRight size={14} />
      </Link>
      {entry.metrics && (
        <div className="entry-metrics">
          {Object.entries(entry.metrics).map(([k, v]) => (
            <span key={k}>
              {v} {metricUnits[k as keyof typeof metricUnits]}
            </span>
          ))}
        </div>
      )}
      <p className="excerpt">{excerpt}</p>
      {image && <LocalImage src={image} alt={entry.title} compact />}
      {!!entry.tags?.length && (
        <div className="tags">
          {entry.tags.map((t) => (
            <span key={t}>#{t}</span>
          ))}
        </div>
      )}
    </article>
  );
}
export function EntryList({
  entries,
  activities,
  compact = false,
}: {
  entries: Entry[];
  activities: Activity[];
  compact?: boolean;
}) {
  if (!entries.length)
    return (
      <div className="empty">
        <FileText size={28} />
        <h3>留一点空间给今天</h3>
        <p>这里还没有记录。发生的事，随时可以写下来。</p>
      </div>
    );
  return (
    <div className="entry-list">
      {ordered(entries).map((e, i, all) => (
        <div key={e.id}>
          {!e.started_at && (i === 0 || all[i - 1].started_at) && (
            <div className="untimed-label">未设时间</div>
          )}
          <EntryCard
            entry={e}
            activity={activities.find((a) => a.id === e.activity_id)}
            compact={compact}
          />
        </div>
      ))}
    </div>
  );
}
export function MonthlySummary({
  month,
  entries,
  activities,
}: {
  month: string;
  entries: Entry[];
  activities: Activity[];
}) {
  return (
    <section className="monthly-summary">
      <div className="section-heading">
        <h2>这个月的积累</h2>
        <span>{month}</span>
      </div>
      <div className="summary-grid">
        {activities.map((a) => {
          const s = summarize(
              entries.filter(
                (e) => e.activity_id === a.id && e.date.startsWith(month),
              ),
            ),
            metric = a.metrics.includes("distance_km")
              ? "distance_km"
              : "duration_min";
          return (
            <Link
              key={a.id}
              href={`/activities/${a.id}?year=${month.slice(0, 4)}&month=${month}`}
              className="summary-item"
              style={tone(a.color)}
            >
              <span className="summary-name">
                <i className="dot" />
                {a.name}
                <ArrowUpRight size={13} />
              </span>
              <strong>
                {s.count}
                <small> 次</small>
              </strong>
              <p>
                {s.days} 天 · {s.sums[metric] ?? "—"} {metricUnits[metric]}
              </p>
              <div className="summary-accent" />
            </Link>
          );
        })}
      </div>
    </section>
  );
}
export function Heatmap({
  activity,
  entries,
  year,
}: {
  activity: Activity;
  entries: Entry[];
  year: number;
}) {
  const dates = yearDays(year),
    today = localDate(),
    counts = new Map<string, Entry[]>();
  for (const e of entries)
    if (e.activity_id === activity.id) {
      const list = counts.get(e.date) ?? [];
      list.push(e);
      counts.set(e.date, list);
    }
  const weeks = dates.length / 7;
  return (
    <div className="heatmap-wrap" style={tone(activity.color)}>
      <div className="heatmap-scroll">
        <div className="heatmap-inner" style={{ width: weeks * 15 + 24 }}>
          <div
            className="heat-months"
            style={{ gridTemplateColumns: `repeat(${weeks}, 15px)` }}
          >
            {dates.flatMap((d, i) =>
              d?.endsWith("-01")
                ? [
                    <span key={d} style={{ gridColumn: Math.floor(i / 7) + 1 }}>
                      {Number(d.slice(5, 7))}月
                    </span>,
                  ]
                : [],
            )}
          </div>
          <div className="heat-body">
            <div className="heat-weekdays">
              <span>一</span>
              <span />
              <span>三</span>
              <span />
              <span>五</span>
              <span />
              <span>日</span>
            </div>
            <div
              className="heat-grid"
              style={{ gridTemplateColumns: `repeat(${weeks},12px)` }}
            >
              {dates.map((d, i) => {
                if (!d) return <span key={i} className="heat-cell outside" />;
                const es = counts.get(d) ?? [],
                  count = es.length,
                  summary = summarize(es),
                  tip = `${d} · ${count} 次${summary.sums.duration_min !== null ? " · " + summary.sums.duration_min + " min" : ""}${summary.sums.distance_km !== null ? " · " + summary.sums.distance_km + " km" : ""}`;
                const style = count
                  ? {
                      background: `color-mix(in srgb, ${activity.color} ${[0, 32, 52, 72, 100][Math.min(count, 4)]}%, white)`,
                    }
                  : {};
                return d > today ? (
                  <span
                    key={d}
                    className="heat-cell future"
                    aria-label={d + "，未来日期"}
                  />
                ) : (
                  <Link
                    key={d}
                    className={`heat-cell ${d === today ? "today" : ""}`}
                    style={style}
                    href={`/activities/${activity.id}?year=${year}&month=${d.slice(0, 7)}&date=${d}`}
                    aria-label={tip}
                    title={tip}
                  >
                    <span className="heat-tip" role="tooltip">
                      {tip}
                    </span>
                  </Link>
                );
              })}
            </div>
          </div>
        </div>
      </div>
      <div className="heat-footer">
        <span>每一格，都是一天</span>
        <div className="heat-key">
          <span>未记录</span>
          {[0, 32, 52, 72, 100].map((v, i) => (
            <i
              key={v}
              style={{
                background: v
                  ? `color-mix(in srgb, ${activity.color} ${v}%, white)`
                  : "#edf0f2",
              }}
              title={i === 4 ? "4+ 次" : i + " 次"}
            />
          ))}
          <span>4+ 次</span>
        </div>
      </div>
    </div>
  );
}
export function Stats({
  entries,
  activity,
}: {
  entries: Entry[];
  activity: Activity;
}) {
  const s = summarize(entries);
  return (
    <div className="stats-row">
      <div>
        <span>活动次数</span>
        <strong>
          {s.count}
          <small> 次</small>
        </strong>
      </div>
      <div>
        <span>活跃天数</span>
        <strong>
          {s.days}
          <small> 天</small>
        </strong>
      </div>
      {activity.metrics.map((key) => (
        <div key={key}>
          <span>累计{metricNames[key]}</span>
          <strong>
            {s.sums[key] ?? "—"}
            <small> {metricUnits[key]}</small>
          </strong>
        </div>
      ))}
    </div>
  );
}
export function DayTitle({
  date,
  entries,
}: {
  date: string;
  entries: Entry[];
}) {
  return (
    <div className="agenda-title">
      <p className="eyebrow">这一天</p>
      <h2>{dayLabel(date)}</h2>
      <p>
        {entries.filter((e) => e.kind === "event").length} 次活动 ·{" "}
        {entries.filter((e) => e.kind === "journal").length} 篇日记
      </p>
    </div>
  );
}
