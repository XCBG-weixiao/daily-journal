"use client";
export default function ErrorPage({
  error,
  reset,
}: {
  error: Error;
  reset: () => void;
}) {
  return (
    <div className="error-panel">
      <h1>暂时无法读取记录</h1>
      <p>{error.message}</p>
      <button className="button" onClick={reset}>
        重新读取
      </button>
    </div>
  );
}
