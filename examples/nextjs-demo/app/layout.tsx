import type { ReactNode } from "react";

export const metadata = {
  title: "VibeFlow Next.js Demo",
  description: "Product catalog + review submission via server action.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <main>{children}</main>
      </body>
    </html>
  );
}
