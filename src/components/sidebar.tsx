"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  CalendarDays,
  Grid2X2,
  Search,
  Plus,
  NotebookPen,
  FolderOpen,
} from "lucide-react";
export default function Sidebar() {
  const pathname = usePathname();
  return (
    <aside className="sidebar">
      <Link href="/calendar" className="brand">
        <span className="brand-icon">
          <NotebookPen size={20} />
        </span>
        <span>
          日常<small>DAILY JOURNAL</small>
        </span>
      </Link>
      <Link href="/entries/new" className="button primary sidebar-add">
        <Plus size={16} />
        记录一下
      </Link>
      <div className="nav-label">我的记录</div>
      <nav>
        <Link
          className={
            ["/calendar", "/timeline"].includes(pathname) ? "active" : ""
          }
          href="/calendar"
        >
          <CalendarDays size={18} />
          时间
        </Link>
        <Link
          className={pathname.startsWith("/activities") ? "active" : ""}
          href="/activities"
        >
          <Grid2X2 size={18} />
          活动
        </Link>
        <Link className={pathname === "/search" ? "active" : ""} href="/search">
          <Search size={18} />
          搜索
        </Link>
      </nav>
      <div className="sidebar-bottom">
        <FolderOpen size={15} />
        <span>
          写在自己的文件里<small>Markdown · 本地存储</small>
        </span>
      </div>
    </aside>
  );
}
