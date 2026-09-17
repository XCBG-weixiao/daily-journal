import { Search as SearchIcon } from "lucide-react";
import { loadSnapshot } from "@/lib/content/load";
import { PageHeader, EntryCard } from "@/components/ui";
export default async function Search({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const q = (await searchParams).q?.trim() ?? "",
    data = await loadSnapshot(),
    results = q
      ? data.entries.filter((e) =>
          [e.title, e.body, ...(e.tags ?? [])]
            .join("\n")
            .toLocaleLowerCase()
            .includes(q.toLocaleLowerCase()),
        )
      : [];
  return (
    <>
      <PageHeader
        eyebrow="FIND A MOMENT"
        title="搜索"
        description="在标题、正文和标签中，找回一个片段。"
      />
      <form className="search-form">
        <SearchIcon size={20} />
        <input
          aria-label="搜索记录"
          name="q"
          defaultValue={q}
          placeholder="试试：公园、阅读，或某个想法…"
        />
        <button className="button primary">搜索</button>
      </form>
      {q && <p className="search-count">找到 {results.length} 条记录</p>}
      <div className="search-results">
        {results.map((e) => (
          <section className="panel" key={e.id}>
            <p className="eyebrow">{e.date}</p>
            <EntryCard
              entry={e}
              activity={data.activities.find((a) => a.id === e.activity_id)}
            />
          </section>
        ))}
      </div>
      {q && !results.length && (
        <div className="empty">没有找到匹配记录，试试其他关键词。</div>
      )}
    </>
  );
}
