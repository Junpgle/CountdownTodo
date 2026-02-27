// vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite' // <--- 引入插件

export default defineConfig({
  plugins: [
    react(),
    tailwindcss() as any, // <--- 添加 as any 解决类型冲突
  ],
})