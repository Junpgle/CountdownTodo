import { useEffect, useRef, useImperativeHandle, forwardRef } from 'react';

// 生产 site key（所有环境统一使用）
const TURNSTILE_SITE_KEY = '0x4AAAAAADkYYUiQdEWVhVYh';

interface TurnstileWidgetProps {
  action?: string;
  onVerified: (token: string) => void;
  onExpired?: () => void;
  onError?: (message: string) => void;
}

export interface TurnstileWidgetRef {
  reset: () => void;
}

declare global {
  interface Window {
    turnstile?: {
      render: (container: string | HTMLElement, options: Record<string, unknown>) => string;
      reset: (widgetId: string) => void;
      remove: (widgetId: string) => void;
    };
  }
}

export const TurnstileWidget = forwardRef<TurnstileWidgetRef, TurnstileWidgetProps>(
  ({ action = 'verify', onVerified, onExpired, onError }, ref) => {
    const containerRef = useRef<HTMLDivElement>(null);
    const widgetIdRef = useRef<string | null>(null);
    const renderedRef = useRef(false);

    // 所有回调和配置都用 ref，不进 useEffect 依赖
    const configRef = useRef({ action, onVerified, onExpired, onError });
    configRef.current = { action, onVerified, onExpired, onError };

    // 暴露 reset 给父组件
    useImperativeHandle(ref, () => ({
      reset: () => {
        if (window.turnstile && widgetIdRef.current) {
          try {
            window.turnstile.reset(widgetIdRef.current);
          } catch (_) {}
        }
      },
    }));

    useEffect(() => {
      // 已渲染过就跳过（StrictMode 第二次 mount 时不再重复）
      if (renderedRef.current) return;

      let cancelled = false;

      function renderWidget() {
        if (cancelled || renderedRef.current || !window.turnstile || !containerRef.current) return;

        try {
          const id = window.turnstile.render(containerRef.current!, {
            sitekey: TURNSTILE_SITE_KEY,
            action: configRef.current.action,
            callback: (token: string) => {
              if (!cancelled) {
                console.log('[Turnstile] ✅ 验证成功 (token length:', token.length, ')');
                configRef.current.onVerified(token);
              }
            },
            'expired-callback': () => {
              if (!cancelled) {
                console.log('[Turnstile] ⏰ token 过期');
                configRef.current.onExpired?.();
              }
            },
            'error-callback': (e?: string) => {
              if (!cancelled) {
                console.warn('[Turnstile] ❌ 错误:', e);
                configRef.current.onError?.(e || '验证加载失败');
              }
            },
          });

          widgetIdRef.current = id;
          renderedRef.current = true;
          console.log('[Turnstile] 🎯 渲染完成，widgetId:', id);
        } catch (e) {
          console.warn('[Turnstile] 渲染异常:', e);
        }
      }

      function waitForScript() {
        if (window.turnstile) {
          renderWidget();
          return;
        }

        const existing = document.querySelector(
          'script[src="https://challenges.cloudflare.com/turnstile/v0/api.js"]'
        );

        if (existing) {
          const timer = setInterval(() => {
            if (cancelled) { clearInterval(timer); return; }
            if (window.turnstile) {
              clearInterval(timer);
              renderWidget();
            }
          }, 100);
          setTimeout(() => clearInterval(timer), 10000);
        } else {
          const s = document.createElement('script');
          s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
          s.async = true;
          s.defer = true;
          s.onload = renderWidget;
          s.onerror = () => {
            if (!cancelled) configRef.current.onError?.('无法加载验证服务');
          };
          document.head.appendChild(s);
        }
      }

      waitForScript();

      return () => {
        cancelled = true;
        if (widgetIdRef.current && window.turnstile) {
          try { window.turnstile.remove(widgetIdRef.current); } catch (_) {}
          widgetIdRef.current = null;
          renderedRef.current = false;
        }
      };
    }, []); // 空依赖，只在首次 mount 执行

    return (
      <div className="w-full">
        <div ref={containerRef} />
      </div>
    );
  }
);

TurnstileWidget.displayName = 'TurnstileWidget';
