import Link from "next/link";
import { notFound } from "next/navigation";
import { Pencil } from "lucide-react";
import { loadSnapshot } from "@/lib/content/load";
import { timeLabel } from "@/lib/content/dates";
import { metricUnits } from "@/lib/content/schema";
import Markdown, { LocalImage } from "@/components/markdown";
export default async function EntryPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params,
    data = await loadSnapshot(),
    e = data.entries.find((e) => e.id === id);
  if (!e) notFound();
  const a = data.activities.find((a) => a.id === e.activity_id);
  return (
    <div className="reader">
      <div className="reader-nav">
        <Link
          className="breadcrumb"
          href={`/calendar?date=${e.date}&month=${e.date.slice(0, 7)}`}
        >
          ← 返回这一天
        </Link>
        <Link className="button" href={`/entries/${id}/edit`}>
          <Pencil size={14} />
          编辑记录
        </Link>
      </div>
      <article className="panel reader-paper">
        <div className="reader-meta">
          <span>{e.date}</span>
          <span>{timeLabel(e.started_at)}</span>
          {a ? (
            <Link
              href={`/activities/${a.id}?year=${e.date.slice(0, 4)}&month=${e.date.slice(0, 7)}&date=${e.date}`}
            >
              {a.icon} {a.name}
            </Link>
          ) : (
            <span>日记</span>
          )}
        </div>
        <h1>{e.title}</h1>
        {e.metrics && (
          <div className="reader-metrics">
            {Object.entries(e.metrics).map(([k, v]) => (
              <span key={k}>
                {v} <small>{metricUnits[k as keyof typeof metricUnits]}</small>
              </span>
            ))}
          </div>
        )}
        {e.cover && <LocalImage src={e.cover} alt={e.title} />}
        <Markdown body={e.body} />
        <div className="tags reader-tags">
          {e.tags?.map((t) => (
            <Link key={t} href={`/search?q=${encodeURIComponent(t)}`}>
              #{t}
            </Link>
          ))}
        </div>
      </article>
    </div>
  );
}
