import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

/**
 * Cloudflare Pages: writes dist/_headers with security headers and a CSP that allows the API origin
 * (VITE_API_BASE, e.g. https://api-thuetab.hidev.dev) for fetch, WebSocket and images.
 * The backend-served build ignores this file (FastAPI sends its own headers).
 */
function pagesHeaders(apiBase) {
  return {
    name: 'thuetab-pages-headers',
    apply: 'build',
    generateBundle() {
      const api = (apiBase || '').trim().replace(/\/+$/, '');
      const ws = api.replace(/^http/, 'ws');
      const extra = s => (s ? ' ' + s : '');
      const csp = [
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        `img-src 'self' blob: data: https://qr.sepay.vn${extra(api)}`,
        `connect-src 'self'${extra(api)}${extra(ws)}`,
        "font-src 'self'",
        "manifest-src 'self'",
        "worker-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'"
      ].join('; ');
      const headers = [
        '/*',
        `  Content-Security-Policy: ${csp}`,
        '  X-Content-Type-Options: nosniff',
        '  X-Frame-Options: DENY',
        '  Referrer-Policy: strict-origin-when-cross-origin',
        '  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()',
        '  Cross-Origin-Opener-Policy: same-origin',
        '/assets/*',
        '  Cache-Control: public, max-age=31536000, immutable',
        '/index.html',
        '  Cache-Control: no-cache',
        '/manifest.webmanifest',
        '  Cache-Control: public, max-age=3600',
        ''
      ].join('\n');
      this.emitFile({ type: 'asset', fileName: '_headers', source: headers });
    }
  };
}

export default defineConfig(({ mode }) => {
  // VITE_API_BASE may come from the environment (Pages build settings) or a .env file.
  const env = { ...loadEnv(mode, process.cwd(), ''), ...process.env };
  return {
    plugins: [react(), pagesHeaders(env.VITE_API_BASE)],
    server: {
      port: 5173,
      // Same-origin dev: /api (and the viewer's WebSocket) are proxied to the local backend.
      proxy: { '/api': { target: 'http://127.0.0.1:8000', ws: true } },
      // src/tokens.js imports ../design/tokens.json and ../design/fonts (inside the repo), shared with the Godot client.
      fs: { allow: ['..'] }
    }
  };
});
