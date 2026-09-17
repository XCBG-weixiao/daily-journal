import Link from "next/link";
import { loadSnapshot } from "@/lib/content/load";
import { getDate, getMonth, localDate } from "@/lib/content/dates";
import {
  AddLink,
  Calendar,
  DayTitle,
  EntryList,
  Legend,
  MonthlySummary,
  PageHeader,
  Period,
} from "@/components/ui";
export default async function CalendarPage({
  searchParams,
}: {
  searchParams: Promise<{ date?: string; month?: string }>;
}) {
  const q = await searchParams,
    today = localDate(),
    month = getMonth(q.month, today.slice(0, 7)),
    date = getDate(q.date, month === today.slice(0, 7) ? today : month + "-01"),
    data = await loadSnapshot(),
    entries = data.entries.filter((e) => e.date === date);
  return (
    <>
      <PageHeader
        eyebrow="YOUR DAYS, IN VIEW"
        title="时间"
        description="把日子展开，看看发生了什么。"
      >
        <AddLink date={date} />
      </PageHeader>
      <div className="view-toolbar">
        <div className="segmented">
          <Link
            className="selected"
            href={`/calendar?month=${month}&date=${date}`}
          >
            月历
          </Link>
          <Link href={`/timeline?date=${date}`}>时间轴</Link>
        </div>
        <div className="toolbar-right">
          <Link
            className="button small"
            href={`/calendar?month=${today.slice(0, 7)}&date=${today}`}
          >
            今天
          </Link>
          <Period month={month} />
        </div>
      </div>
      <div className="calendar-layout">
        <section className="panel agenda">
          <DayTitle date={date} entries={entries} />
          <EntryList entries={entries} activities={data.activities} compact />
          {date <= today && (
            <Link className="text-link" href={`/entries/new?date=${date}`}>
              ＋ 为这天添加记录
            </Link>
          )}
        </section>
        <div className="calendar-main">
          <section className="panel calendar-panel">
            <div className="section-heading">
              <h2>{Number(month.slice(5))} 月的日常</h2>
              <span>{month.slice(0, 4)}</span>
            </div>
            <Legend activities={data.activities} />
            <Calendar
              month={month}
              date={date}
              entries={data.entries}
              activities={data.activities}
            />
          </section>
          <MonthlySummary
            month={month}
            entries={data.entries}
            activities={data.activities}
          />
        </div>
      </div>
    </>
  );
}
