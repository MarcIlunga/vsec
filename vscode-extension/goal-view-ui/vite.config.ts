import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { copyFileSync } from 'fs'
import { resolve } from 'path'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [
    react(),
    // Copy codicons CSS to output directory
    {
      name: 'copy-codicons',
      writeBundle() {
        const src = resolve(__dirname, 'node_modules/@vscode/codicons/dist/codicon.css');
        const dest = resolve(__dirname, '../media/goal-view/codicon.css');
        copyFileSync(src, dest);
        console.log('Copied codicons CSS to build output');
      }
    }
  ],
  build: {
    outDir: '../media/goal-view',
    emptyOutDir: true,
    cssCodeSplit: false, // Bundle all CSS into one file
    rollupOptions: {
      output: {
        entryFileNames: 'goal-view.js',
        chunkFileNames: 'goal-view-chunk.js',
        assetFileNames: (assetInfo) => {
          // Generate separate files with proper names
          if (assetInfo.name?.endsWith('.css')) {
            return 'goal-view.css';
          }
          return 'goal-view.[ext]';
        },
        // Disable inlining of assets
        inlineDynamicImports: false
      }
    },
    // Ensure CSS is extracted to separate file
    assetsInlineLimit: 0
  }
})