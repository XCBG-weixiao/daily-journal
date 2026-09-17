import { notFound } from "next/navigation";
import { loadSnapshot } from "@/lib/content/load";
import Editor from "@/components/editor";
export default async function EditEntry({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params,
    data = await loadSnapshot(),
    entry = data.entries.find((e) => e.id === id);
  if (!entry) notFound();
  return (
    <Editor
      activities={data.activities}
      id={id}
      entry={entry}
      initialDate={entry.date}
    />
  );
}
