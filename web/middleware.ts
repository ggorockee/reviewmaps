import { NextRequest, NextResponse } from 'next/server';

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // app-ads.txt 요청 처리 -- 매우중요
  if (pathname === "/app-ads.txt") {
    return new NextResponse(
      "google.com, pub-8516861197467665, DIRECT, f08c47fec0942fa0\n",
      {
        headers: {
          "Content-Type": "text/plain",
          "Cache-Control": "public, max-age=3600",
        },
      }
    );
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    '/app-ads.txt',
  ],
};
