"use client";
import { useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { imageUrl } from "@/lib/content/image-url";
export function LocalImage({
  src,
  alt = "",
  compact = false,
}: {
  src?: string;
  alt?: string;
  compact?: boolean;
}) {
  const [failed, setFailed] = useState(false),
    url = imageUrl(src);
  if (!url || failed)
    return <span className="image-error">图片缺失或路径无效：{src}</span>;
  // Files are served by the bounded image endpoint; preserve the user's original image.
  return (
    <a
      href={url}
      target="_blank"
      rel="noreferrer"
      className={compact ? "image-link compact" : "image-link"}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={url} alt={alt} onError={() => setFailed(true)} loading="lazy" />
    </a>
  );
}
export default function Markdown({ body }: { body: string }) {
  return (
    <div className="prose">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        skipHtml
        components={{
          img: ({ src, alt }) => (
            <LocalImage
              src={typeof src === "string" ? src : undefined}
              alt={alt}
            />
          ),
          a: ({ href, children }) => (
            <a href={href} target="_blank" rel="noreferrer">
              {children}
            </a>
          ),
        }}
      >
        {body}
      </ReactMarkdown>
    </div>
  );
}
