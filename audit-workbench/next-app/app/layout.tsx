import type { Metadata } from "next";
import "@/styles/globals.css";
export const metadata: Metadata = {title:"稽核工作进度看板 · 演示版",description:"虚构数据演示：团队台账、阶段历史、成果和周报"};
export default function RootLayout({children}:{children:React.ReactNode}) {
  return <html lang="zh-CN"><body>{children}</body></html>;
}
