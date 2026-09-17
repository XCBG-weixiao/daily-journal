import Link from "next/link";
import { loadSnapshot } from "@/lib/content/load";
import { dayLabel, getDate, localDate, shiftDay } from "@/lib/content/dates";
import { AddLink, EntryList, PageHeader } from "@/components/ui";
export default async function Timeline({
  searchParams,
}: {
  searchParams: Promise<{ date?: string }>;
}) {
  const q = await searchParams,
    date = getDate(q.date, localDate()),
    data = await loadSnapshot(),
    days = Array.from({ length: 7 }, (_, i) => shiftDay(date, -i));
  return (
    <>
      <PageHeader
        eyebrow="A LITTLE EVERY DAY"
        title="时间轴"
        description="记录发生的事，也记录当时的自己。"
      >
        <AddLink />
      </PageHeader>
      <div className="view-toolbar">
        <div className="segmented">
          <Link href={`/calendar?month=${date.slice(0, 7)}&date=${date}`}>
            月历
          </Link>
          <Link className="selected" href={`/timeline?date=${date}`}>
            时间轴
          </Link>
        </div>
        <div className="toolbar-right">
          <Link
            className="button"
            href={`/timeline?date=${shiftDay(date, -7)}`}
          >
            ← 前七天
          </Link>
          <Link className="button" href={`/timeline?date=${shiftDay(date, 7)}`}>
            后七天 →
          </Link>
        </div>
      </div>
      <div className="timeline">
        {days.map((day) => (
          <section className="timeline-day" key={day}>
            <div className="timeline-date">
              <span>{day.slice(0, 7)}</span>
              <strong>{day.slice(8)}</strong>
              <span>{dayLabel(day).split("日")[1]}</span>
            </div>
            <div className="panel">
              <EntryList
                entries={data.entries.filter((e) => e.date === day)}
                activities={data.activities}
              />
            </div>
          </section>
        ))}
      </div>
    </>
  );
}
