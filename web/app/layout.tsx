import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "리뷰맵 - 내 주변 체험단을 한 번에",
  description: "리뷰맵은 내 현재 위치를 기준으로 가까운 체험단을 지도와 리스트로 모아 보여주는 앱입니다. 지도를 움직이고 이 위치로 검색만 누르면, 해당 범위의 체험단을 빠르게 확인하고 원본 페이지로 바로 이동할 수 있어요.",
  keywords: ["체험단", "리뷰", "지도", "앱", "모바일", "체험단 찾기", "리뷰맵"],
  authors: [{ name: "리뷰맵" }],
  creator: "리뷰맵",
  publisher: "리뷰맵",
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  metadataBase: new URL('https://review-maps.com'),
  alternates: {
    canonical: '/',
  },
  verification: {
    google: 'your-google-verification-code',
  },
  openGraph: {
    title: "리뷰맵 - 내 주변 체험단을 한 번에",
    description: "리뷰맵은 내 현재 위치를 기준으로 가까운 체험단을 지도와 리스트로 모아 보여주는 앱입니다.",
    url: 'https://review-maps.com',
    siteName: '리뷰맵',
    images: [
      {
        url: 'https://review-maps.com/assets/images/logo.png',
        width: 1200,
        height: 630,
        alt: '리뷰맵 앱 화면 - 내 주변 체험단을 한 번에',
        type: 'image/png',
      },
    ],
    locale: 'ko_KR',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: "리뷰맵 - 내 주변 체험단을 한 번에",
    description: "리뷰맵은 내 현재 위치를 기준으로 가까운 체험단을 지도와 리스트로 모아 보여주는 앱입니다.",
    images: ['https://review-maps.com/assets/images/logo.png'],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  icons: {
    icon: '/favicon.png',
    shortcut: '/favicon.png',
    apple: '/favicon.png',
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
