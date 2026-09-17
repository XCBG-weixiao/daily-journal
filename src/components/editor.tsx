"use client";
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ImagePlus, Save, ArrowLeft } from "lucide-react";
import Link from "next/link";
import type { Activity, Entry, MetricKey } from "@/lib/content/schema";
import { metricNames, metricUnits } from "@/lib/content/schema";
import { localDate, timeLabel } from "@/lib/content/dates";
import Markdown from "./markdown";
export default function Editor({
  activities,
  id,
  entry,
  initialDate,
  initialActivity,
}: {
  activities: Activity[];
  id: string;
  entry?: Entry;
  initialDate: string;
  initialActivity?: string;
}) {
  const router = useRouter(),
    textarea = useRef<HTMLTextAreaElement>(null),
    fileInput = useRef<HTMLInputElement>(null);
  const [kind, setKind] = useState<"event" | "journal">(
      entry?.kind ?? (initialActivity ? "event" : "journal"),
    ),
    [title, setTitle] = useState(entry?.title ?? ""),
    [date, setDate] = useState(entry?.date ?? initialDate),
    [time, setTime] = useState(
      entry?.started_at ? timeLabel(entry.started_at) : "",
    ),
    [activity, setActivity] = useState(
      entry?.activity_id ?? initialActivity ?? activities[0]?.id ?? "",
    ),
    [values, setValues] = useState<Record<string, string>>(
      Object.fromEntries(
        Object.entries(entry?.metrics ?? {}).map(([k, v]) => [k, String(v)]),
      ),
    ),
    [tags, setTags] = useState(entry?.tags?.join(", ") ?? ""),
    [cover, setCover] = useState(entry?.cover ?? ""),
    [body, setBody] = useState(entry?.body ?? ""),
    [tab, setTab] = useState("write"),
    [error, setError] = useState(""),
    [saving, setSaving] = useState(false),
    [uploading, setUploading] = useState(false);
  const chosen = activities.find((a) => a.id === activity);
  async function save() {
    setError("");
    setSaving(true);
    try {
      const meta = {
        schema_version: 1,
        id,
        kind,
        title,
        date,
        ...(time ? { started_at: `${date}T${time}:00+08:00` } : {}),
        ...(kind === "event"
          ? {
              activity_id: activity,
              metrics: Object.fromEntries(
                (chosen?.metrics ?? [])
                  .filter((k) => values[k] !== undefined && values[k] !== "")
                  .map((k) => [k, Number(values[k])]),
              ),
            }
          : {}),
        tags: tags
          .split(/[,，]/)
          .map((t) => t.trim())
          .filter(Boolean),
        ...(cover ? { cover } : {}),
      };
      const response = await fetch("/api/entries", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ meta, body, expectedHash: entry?.hash ?? null }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      router.push(`/entries/${id}`);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }
  async function upload(file: File) {
    setUploading(true);
    setError("");
    const start = textarea.current?.selectionStart ?? body.length,
      end = textarea.current?.selectionEnd ?? start;
    try {
      const form = new FormData();
      form.set("file", file);
      form.set("id", id);
      const response = await fetch("/api/uploads", {
          method: "POST",
          body: form,
        }),
        result = await response.json();
      if (!response.ok) throw new Error(result.error);
      const alt = file.name.replace(/[\[\]\\\n]/g, "");
      const insertion = `\n![${alt}](${result.path})\n`;
      setBody(
        (current) => current.slice(0, start) + insertion + current.slice(end),
      );
      setTab("write");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setUploading(false);
      if (fileInput.current) fileInput.current.value = "";
    }
  }
  return (
    <div className="editor">
      <div className="reader-nav">
        <Link
          className="breadcrumb"
          href={
            entry
              ? `/entries/${id}`
              : `/calendar?month=${date.slice(0, 7)}&date=${date}`
          }
        >
          <ArrowLeft size={15} />
          返回
        </Link>
        <button
          type="button"
          onClick={save}
          className="button primary"
          disabled={saving || uploading}
        >
          <Save size={15} />
          {saving ? "正在保存…" : "保存记录"}
        </button>
      </div>
      <div className="editor-title">
        <p className="eyebrow">
          {entry ? "EDIT A MOMENT" : "MAKE A LITTLE NOTE"}
        </p>
        <h1>{entry ? "编辑记录" : "记录此刻"}</h1>
        <p className="subtitle">文字、图片和一点感受，都留在这里。</p>
      </div>
      {error && (
        <div className="form-error" role="alert">
          {error}
        </div>
      )}
      <div className="panel editor-paper">
        <div className="editor-fields">
          <label>
            记录类型
            <select
              value={kind}
              onChange={(e) => setKind(e.target.value as "event" | "journal")}
            >
              <option value="journal">日记</option>
              <option value="event">活动</option>
            </select>
          </label>
          {kind === "event" && (
            <label>
              活动
              <select
                value={activity}
                onChange={(e) => {
                  setActivity(e.target.value);
                  setValues({});
                }}
              >
                {activities.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.icon} {a.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          <label>
            日期
            <input
              type="date"
              value={date}
              max={localDate()}
              onChange={(e) => setDate(e.target.value)}
            />
          </label>
          <label>
            时间 <span>可选</span>
            <input
              type="time"
              value={time}
              onChange={(e) => setTime(e.target.value)}
            />
          </label>
          {kind === "event" &&
            chosen?.metrics.map((key: MetricKey) => (
              <label key={key}>
                {metricNames[key]} <span>{metricUnits[key]}</span>
                <input
                  type="number"
                  min="0"
                  step={key === "pages" ? "1" : "any"}
                  value={values[key] ?? ""}
                  placeholder="未填写"
                  onChange={(e) =>
                    setValues({ ...values, [key]: e.target.value })
                  }
                />
              </label>
            ))}
        </div>
        <input
          className="title-input"
          aria-label="标题"
          placeholder="为这段记录起个标题"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />
        <div className="editor-toolbar">
          <div className="segmented">
            <button
              type="button"
              className={tab === "write" ? "selected" : ""}
              onClick={() => setTab("write")}
            >
              Markdown
            </button>
            <button
              type="button"
              className={tab === "preview" ? "selected" : ""}
              onClick={() => setTab("preview")}
            >
              预览
            </button>
            <button
              type="button"
              className={tab === "split" ? "selected" : ""}
              onClick={() => setTab("split")}
            >
              分栏
            </button>
          </div>
          <button
            className="button small"
            type="button"
            onClick={() => fileInput.current?.click()}
            disabled={uploading}
          >
            <ImagePlus size={15} />
            {uploading ? "上传中…" : "添加图片"}
          </button>
          <input
            ref={fileInput}
            type="file"
            hidden
            accept="image/png,image/jpeg,image/webp"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void upload(f);
            }}
            aria-label="上传图片"
          />
        </div>
        <div
          className={`editor-body ${tab === "split" ? "split" : ""}`}
          onDragOver={(e) => e.preventDefault()}
          onDrop={(e) => {
            e.preventDefault();
            const f = e.dataTransfer.files[0];
            if (f && !uploading) void upload(f);
          }}
        >
          {tab !== "preview" && (
            <textarea
              aria-label="Markdown 正文"
              ref={textarea}
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder={"今天发生了什么？\n\n可以把图片拖到这里。"}
              spellCheck={false}
            />
          )}
          {tab !== "write" && (
            <div className="editor-preview">
              <Markdown body={body} />
            </div>
          )}
        </div>
        <div className="editor-bottom">
          <label>
            标签{" "}
            <input
              value={tags}
              onChange={(e) => setTags(e.target.value)}
              placeholder="用逗号分隔，例如：户外, 公园"
            />
          </label>
          <details>
            <summary>封面图片（可选）</summary>
            <label>
              本地图片相对路径
              <input
                value={cover}
                onChange={(e) => setCover(e.target.value)}
                placeholder="../assets/记录ID/图片名.png"
              />
            </label>
          </details>
          <p className="muted">
            支持 PNG / JPG / WebP，每张最多 10 MB。保存后写入本地 Markdown。
          </p>
        </div>
      </div>
    </div>
  );
}
