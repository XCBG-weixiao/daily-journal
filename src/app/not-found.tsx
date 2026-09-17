import Link from "next/link";
export default function NotFound() {
  return (
    <div className="empty">
      <h1>没有找到这条记录</h1>
      <p>文件可能已被移动或删除。</p>
      <Link className="button" href="/calendar">
        返回日历
      </Link>
    </div>
  );
}
