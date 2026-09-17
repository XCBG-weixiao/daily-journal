import type { Metadata } from "next";
import Sidebar from "@/components/sidebar";
import { loadSnapshot } from "@/lib/content/load";
import "./globals.css";
export const metadata: Metadata = {
  title: "日常 · 个人活动日志",
  description: "以 Markdown 保存生活，从时间与活动重新看见日常。",
};
export const dynamic = "force-dynamic";
export const runtime = "nodejs";
export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  let data, error;
  try {
    data = await loadSnapshot();
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }
  return (
    <html lang="zh-CN">
      <body>
        <div className="app-shell">
          <Sidebar />
          <div className="workspace">
            <div className="topbar">
              <span>给平凡的日子，留一点痕迹。</span>
              <span className="local-status">
                <i />
                本地工作空间
              </span>
            </div>
            {data?.demo && (
              <div className="demo-notice">
                示例内容{" "}
                <span>
                  当前包含演示记录和自制插图。你的记录保存在本地 Markdown
                  文件中。
                </span>
              </div>
            )}
            {!!data?.issues.length && (
              <details className="data-warning" open>
                <summary>
                  数据不完整 · {data.issues.length} 个文件需要检查
                </summary>
                {data.issues.map((i) => (
                  <p key={i.file}>
                    <code>{i.file}</code>：{i.message}
                  </p>
                ))}
              </details>
            )}
            <main className="main">
              {error ? (
                <div className="error-panel">
                  <h1>内容目录尚未就绪</h1>
                  <p>{error}</p>
                </div>
              ) : (
                children
              )}
            </main>
          </div>
        </div>
      </body>
    </html>
  );
}
