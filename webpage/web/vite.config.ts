// vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite' // <--- 引入插件

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(), // <--- 添加插件
  ],
})