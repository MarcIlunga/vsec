import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: '../media/goal-view',
    rollupOptions: {
      output: {
        entryFileNames: 'goal-view.js',
        chunkFileNames: 'goal-view-chunk.js',
        assetFileNames: 'goal-view.[ext]'
      }
    }
  }
})