import { copyFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

let resolvedConfig;

export default defineConfig({
  plugins: [react(), {
    name: 'cloudflare-pages-files',
    apply: 'build',
    configResolved(config) { resolvedConfig = config; },
    writeBundle() {
      const { root, build } = resolvedConfig;
      for (const name of ['_headers', '_redirects']) {
        copyFileSync(resolve(root, 'public', name), resolve(root, build.outDir, name));
      }
    },
  }],
  test: {
    environment: 'jsdom',
    setupFiles: './src/test-setup.js',
    clearMocks: true,
  },
  build: {
    copyPublicDir: false,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('/node_modules/recharts/')) return 'charts';
          if (id.includes('/node_modules/lucide-react/')) return 'icons';
          if (id.includes('/node_modules/react/')) return 'react-vendor';
        },
      },
    },
  },
});
