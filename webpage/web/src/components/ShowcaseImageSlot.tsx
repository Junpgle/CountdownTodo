import { useState, type ReactNode } from 'react';
import { Camera } from 'lucide-react';

interface ShowcaseImageSlotProps {
  src: string;
  alt: string;
  fileNameHint?: string;
  className?: string;
  imgClassName?: string;
  fallback: ReactNode;
}

/**
 * 图文展示槽位：优先尝试懒加载 public 下的真实截图；
 * 截图尚未放入时平滑渲染高保真 UI 预览卡片并标注替换文件名。
 */
export const ShowcaseImageSlot = ({
  src,
  alt,
  fileNameHint,
  className = '',
  imgClassName = 'w-full h-full object-cover',
  fallback,
}: ShowcaseImageSlotProps) => {
  const [loadedSrc, setLoadedSrc] = useState<string | null>(null);
  const [failedSrc, setFailedSrc] = useState<string | null>(null);

  const isLoaded = loadedSrc === src;
  const hasError = failedSrc === src;
  const displayHint = fileNameHint || src.replace(/^\.\//, '');

  return (
    <div className={`relative overflow-hidden ${className}`}>
      {!isLoaded && (
        <div className="relative w-full">
          {fallback}
          {displayHint && (
            <div className="pointer-events-none absolute top-3 right-3 z-20 inline-flex items-center gap-1.5 rounded-full bg-slate-900/75 px-3 py-1 text-[10px] font-bold tracking-wide text-white/90 backdrop-blur-md border border-white/15 shadow-sm">
              <Camera className="w-3 h-3 text-indigo-300" />
              <span>UI 预览 · 可放截图 public/{displayHint}</span>
            </div>
          )}
        </div>
      )}

      {!hasError && (
        <img
          key={src}
          src={src}
          alt={alt}
          loading="lazy"
          onLoad={(e) => {
            if (e.currentTarget.naturalWidth > 0) {
              setLoadedSrc(src);
            } else {
              setFailedSrc(src);
            }
          }}
          onError={() => setFailedSrc(src)}
          className={
            isLoaded
              ? imgClassName
              : 'absolute inset-0 h-full w-full object-cover opacity-0 pointer-events-none'
          }
        />
      )}
    </div>
  );
};
