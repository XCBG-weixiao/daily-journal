import Link from "next/link";
import { notFound } from "next/navigation";
import { loadSnapshot } from "@/lib/content/load";
import {
  getDate,
  getMonth,
  getYear,
  localDate,
  weekday,
} from "@/lib/content/dates";
import { summarize } from "@/lib/content/aggregate";
import {
  AddLink,
  Calendar,
  EntryList,
  Heatmap,
  PageHeader,
  Period,
  Stats,
  YearNav,
  tone,
} from "@/components/ui";
export default async function ActivityDetail({
  params,
  searchParams,
}: {
  params: Promise<{ activityId: string }>;
  searchParams: Promise<{ year?: string; month?: string; date?: string }>;
}) {
  const { activityId } = await params,
    q = await searchParams,
    data = await loadSnapshot(),
    a = data.activities.find((a) => a.id === activityId);
  if (!a) notFound();
  const today = localDate(),
    year = getYear(q.year, +today.slice(0, 4)),
    month = getMonth(q.month, `${year}-${today.slice(5, 7)}`),
    date = q.date ? getDate(q.date, month + "-01") : undefined,
    base = `/activities/${a.id}`,
    all = data.entries.filter((e) => e.activity_id === a.id),
    annual = all.filter((e) => e.date.startsWith(year + "")),
    history = all.filter((e) =>
      date ? e.date === date : e.date.startsWith(month),
    ),
    s = summarize(annual),
    monthly = Array.from(
      { length: 12 },
      (_, i) => annual.filter((e) => +e.date.slice(5, 7) === i + 1).length,
    ),
    weekly = Array.from(
      { length: 7 },
      (_, i) => annual.filter((e) => weekday(e.date) === i).length,
    );
  return (
    <div style={tone(a.color)}>
      <Link href={`/activities?year=${year}`} className="breadcrumb">
        ← 所有活动
      </Link>
      <PageHeader
        eyebrow="ACTIVITY JOURNAL"
        title={`${a.icon} ${a.name}`}
        description={a.body.trim()}
      >
        <AddLink activity={a.id} />
      </PageHeader>
      <div className="view-toolbar">
        <div className="anchor-nav">
          <a href="#overview">年度回顾</a>
          <a href="#history">记录</a>
          <a href="#statistics">统计</a>
        </div>
        <YearNav year={year} base={base} month={month} />
      </div>
      <section id="overview" className="panel">
        <div className="section-heading">
          <h2>{year} 年的积累</h2>
          <span>所选年份</span>
        </div>
        <Stats entries={annual} activity={a} />
        <Heatmap activity={a} entries={annual} year={year} />
      </section>
      <div className="activity-detail-grid" id="history">
        <section className="panel">
          <div className="section-heading">
            <h2>{date ?? month} · 记录</h2>
            <span>{history.length} 次</span>
          </div>
          {date && (
            <div className="history-controls">
              <Link
                className="text-link"
                href={`${base}?year=${year}&month=${month}`}
              >
                查看整月
              </Link>
              <Link
                className="text-link"
                href={`/calendar?month=${date.slice(0, 7)}&date=${date}`}
              >
                这天所有记录 →
              </Link>
            </div>
          )}
          <EntryList entries={history} activities={data.activities} />
        </section>
        <section className="panel detail-calendar">
          <Period month={month} base={base} />
          <Calendar
            month={month}
            date={date}
            entries={all}
            activities={[a]}
            base={base}
          />
        </section>
      </div>
      <section id="statistics" className="panel">
        <div className="section-heading">
          <h2>{year} 年 · 统计</h2>
          <span>
            平均时长 {s.averageDuration ?? "—"} min · {s.samples.duration_min}{" "}
            个有效样本
          </span>
        </div>
        <div className="chart-grid">
          <div>
            <h3>每月活动次数</h3>
            <div className="bar-chart">
              {monthly.map((value, i) => (
                <div key={i} className="bar-column">
                  <span>{value}</span>
                  <i
                    style={{
                      height: `${(value / Math.max(1, ...monthly)) * 100}px`,
                    }}
                  />
                  <small>{i + 1}月</small>
                </div>
              ))}
            </div>
          </div>
          <div>
            <h3>星期分布</h3>
            <div className="bar-chart">
              {weekly.map((value, i) => (
                <div key={i} className="bar-column">
                  <span>{value}</span>
                  <i
                    style={{
                      height: `${(value / Math.max(1, ...weekly)) * 100}px`,
                    }}
                  />
                  <small>{["一", "二", "三", "四", "五", "六", "日"][i]}</small>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
