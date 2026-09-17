import { randomUUID } from "node:crypto";
import { loadSnapshot } from "@/lib/content/load";
import { getDate, localDate } from "@/lib/content/dates";
import Editor from "@/components/editor";
export default async function NewEntry({
  searchParams,
}: {
  searchParams: Promise<{ date?: string; activity?: string }>;
}) {
  const q = await searchParams,
    data = await loadSnapshot();
  return (
    <Editor
      activities={data.activities}
      id={randomUUID()}
      initialDate={getDate(q.date, localDate())}
      initialActivity={q.activity}
    />
  );
}
