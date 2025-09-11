import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: '../media/goal-view',
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