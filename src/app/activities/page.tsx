import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { loadSnapshot } from "@/lib/content/load";
import { getYear, localDate } from "@/lib/content/dates";
import { summarize } from "@/lib/content/aggregate";
import { AddLink, Heatmap, PageHeader, YearNav, tone } from "@/components/ui";
export default async function Activities({
  searchParams,
}: {
  searchParams: Promise<{ year?: string }>;
}) {
  const q = await searchParams,
    year = getYear(q.year, +localDate().slice(0, 4)),
    data = await loadSnapshot();
  return (
    <>
      <PageHeader
        eyebrow="THE THINGS YOU KEEP DOING"
        title="活动"
        description="每一行，都是一件持续发生的事。"
      >
        <AddLink />
      </PageHeader>
      <div className="view-toolbar">
        <span className="muted">
          {data.activities.length} 项活动 · 按日期回顾
        </span>
        <YearNav year={year} />
      </div>
      <div className="activity-stack">
        {data.activities.map((a) => {
          const entries = data.entries.filter(
              (e) => e.activity_id === a.id && e.date.startsWith(year + ""),
            ),
            s = summarize(entries),
            last = [...entries].sort((a, b) => b.date.localeCompare(a.date))[0];
          return (
            <section
              key={a.id}
              className="panel activity-panel"
              style={tone(a.color)}
            >
              <div className="activity-heading">
                <Link
                  href={`/activities/${a.id}?year=${year}`}
                  className="activity-title"
                >
                  <span className="activity-icon">{a.icon}</span>
                  <div>
                    <h2>
                      {a.name}
                      <ArrowUpRight size={16} />
                    </h2>
                    <p>{last ? "最近记录 " + last.date : "这一年还没有记录"}</p>
                  </div>
                </Link>
                <div className="activity-count">
                  <strong>
                    {s.count}
                    <small> 次</small>
                  </strong>
                  <span>{s.days} 个活跃日</span>
                </div>
              </div>
              <Heatmap activity={a} entries={entries} year={year} />
              <Link
                className="text-link"
                href={`/activities/${a.id}?year=${year}`}
              >
                查看月历与全部记录 →
              </Link>
            </section>
          );
        })}
      </div>
    </>
  );
}
