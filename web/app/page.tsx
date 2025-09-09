'use client';

import Image from "next/image";
import Link from "next/link";
import { useState, useRef, useEffect, useCallback } from "react";

export default function Home() {
  const [isDragging, setIsDragging] = useState(false);
  const [startX, setStartX] = useState(0);
  const [scrollLeft, setScrollLeft] = useState(0);
  const [isHovered, setIsHovered] = useState(false);
  const [showPopup, setShowPopup] = useState(false);
  const sliderRef = useRef<HTMLDivElement>(null);
  const animationRef = useRef<number | null>(null);

  const handleMouseDown = (e: React.MouseEvent) => {
    if (!sliderRef.current) return;
    setIsDragging(true);
    setStartX(e.pageX - sliderRef.current.offsetLeft);
    setScrollLeft(sliderRef.current.scrollLeft);
    // 드래그 시작 시 애니메이션 정지
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
    }
  };

  const handleMouseLeave = () => {
    setIsDragging(false);
    setIsHovered(false);
  };

  const handleMouseUp = () => {
    setIsDragging(false);
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!isDragging || !sliderRef.current) return;
    e.preventDefault();
    const x = e.pageX - sliderRef.current.offsetLeft;
    const walk = (x - startX) * 2;
    sliderRef.current.scrollLeft = scrollLeft - walk;
  };

  const handleMouseEnter = () => {
    setIsHovered(true);
    // 호버 시 애니메이션 정지
    if (animationRef.current) {
      cancelAnimationFrame(animationRef.current);
    }
  };

  const handleGooglePlayClick = (e: React.MouseEvent) => {
    e.preventDefault();
    setShowPopup(true);
    setTimeout(() => setShowPopup(false), 3000);
  };

  const startAutoScroll = useCallback(() => {
    if (!sliderRef.current) return;
    
    const scroll = () => {
      if (!sliderRef.current || isDragging || isHovered) return;
      
      const maxScroll = sliderRef.current.scrollWidth - sliderRef.current.clientWidth;
      const currentScroll = sliderRef.current.scrollLeft;
      
      if (currentScroll >= maxScroll) {
        // 끝에 도달하면 처음으로 리셋
        sliderRef.current.scrollLeft = 0;
      } else {
        // 천천히 스크롤 (1.5배 빠르게)
        sliderRef.current.scrollLeft += 1.5;
      }
      
      animationRef.current = requestAnimationFrame(scroll);
    };
    
    animationRef.current = requestAnimationFrame(scroll);
  }, [isDragging, isHovered]);

  useEffect(() => {
    if (!isDragging && !isHovered) {
      startAutoScroll();
    }
    
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [isDragging, isHovered, startAutoScroll]);

  return (
    <div className="min-h-screen bg-white">
      {/* Popup */}
      {showPopup && (
        <div className="fixed inset-0 bg-white/15 backdrop-blur-[2px] flex items-center justify-center z-50">
          <div className="bg-white rounded-2xl p-8 max-w-sm mx-4 shadow-2xl animate-fade-in">
            <div className="text-center">
              <div className="w-16 h-16 bg-yellow-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-2">준비 중입니다</h3>
              <p className="text-gray-600 mb-6">Google Play Store 버전은 현재 준비 중입니다.<br />곧 출시될 예정이니 조금만 기다려주세요!</p>
              <button 
                onClick={() => setShowPopup(false)}
                className="bg-green-600 text-white px-6 py-2 rounded-lg hover:bg-green-700 transition-colors"
              >
                확인
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Header */}
      <header className="bg-white/80 backdrop-blur-sm shadow-sm sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <div className="flex items-center space-x-3">
              <Image
                src="/assets/images/logo.png"
                alt="리뷰맵 로고"
                width={40}
                height={40}
                className="w-8 h-8 sm:w-10 sm:h-10"
              />
              <h1 className="text-xl sm:text-2xl font-bold text-gray-900">리뷰맵</h1>
            </div>
            <nav className="hidden md:flex space-x-8">
              <a href="#features" className="text-gray-600 hover:text-green-600 transition-colors">주요 기능</a>
              <a href="#how-to-use" className="text-gray-600 hover:text-green-600 transition-colors">사용법</a>
              <a href="#screenshots" className="text-gray-600 hover:text-green-600 transition-colors">앱 화면</a>
              <Link href="/privacy" className="text-gray-600 hover:text-green-600 transition-colors">개인정보처리방침</Link>
            </nav>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="relative py-20 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <div className="text-center">
            <h1 className="text-4xl sm:text-5xl md:text-6xl lg:text-7xl font-bold text-gray-900 mb-6 animate-fade-in-up">
              리뷰맵
              <span className="block text-2xl sm:text-3xl md:text-4xl gradient-text mt-2">
                내 주변 체험단을 한 번에
              </span>
            </h1>
            <p className="text-lg sm:text-xl text-gray-600 mb-8 max-w-3xl mx-auto leading-relaxed px-4">
              리뷰할 곳, 아직도 여기저기 돌아다니며 찾고 있나요?<br />
              리뷰맵은 내 현재 위치를 기준으로 가까운 체험단을 지도와 리스트로 모아 보여주는 앱입니다.
            </p>
            <div className="flex flex-col sm:flex-row gap-3 sm:gap-4 justify-center items-center">
              <div className="flex gap-3 sm:hidden">
                <button onClick={handleGooglePlayClick} className="inline-block">
                  <Image
                    src="/assets/images/google-play-badge.png"
                    alt="Google Play에서 다운로드"
                    width={200}
                    height={60}
                    className="h-10 w-auto hover:opacity-80 transition-opacity"
                  />
                </button>
                <a href="https://apps.apple.com/us/app/%EB%A6%AC%EB%B7%B0%EB%A7%B5/id6751343880" target="_blank" rel="noopener noreferrer" className="inline-block">
                  <Image
                    src="/assets/images/app-store-badge.png"
                    alt="App Store에서 다운로드"
                    width={200}
                    height={60}
                    className="h-10 w-auto hover:opacity-80 transition-opacity"
                  />
                </a>
              </div>
              <div className="hidden sm:flex gap-4 items-center">
                <button onClick={handleGooglePlayClick} className="inline-block">
                  <Image
                    src="/assets/images/google-play-badge.png"
                    alt="Google Play에서 다운로드"
                    width={200}
                    height={60}
                    className="h-14 w-auto hover:opacity-80 transition-opacity"
                  />
                </button>
                <a href="https://apps.apple.com/us/app/%EB%A6%AC%EB%B7%B0%EB%A7%B5/id6751343880" target="_blank" rel="noopener noreferrer" className="inline-block">
                  <Image
                    src="/assets/images/app-store-badge.png"
                    alt="App Store에서 다운로드"
                    width={200}
                    height={60}
                    className="h-14 w-auto hover:opacity-80 transition-opacity"
                  />
                </a>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="py-20 bg-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">주요 기능</h2>
            <p className="text-lg sm:text-xl text-gray-600">리뷰맵의 핵심 기능들을 확인해보세요</p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8 animate-fade-in-up">
            <div className="bg-white p-6 sm:p-8 rounded-2xl border border-gray-200 card-hover">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mb-6">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">내 주변 체험단 추천</h3>
              <p className="text-gray-600">위치 권한을 허용하면 지금 있는 곳 주변의 모집 정보를 우선 노출합니다.</p>
            </div>

            <div className="bg-white p-6 sm:p-8 rounded-2xl border border-gray-200 card-hover">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mb-6">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">지도 탐색 검색</h3>
              <p className="text-gray-600">지도를 드래그한 뒤 이 위치로 검색 → 화면 범위 안의 캠페인만 깔끔하게 보기</p>
            </div>

            <div className="bg-white p-6 sm:p-8 rounded-2xl border border-gray-200 card-hover">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mb-6">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">핵심 정보 한눈에</h3>
              <p className="text-gray-600">제공 내역, 마감일(~MM.DD), 거리(km) 등을 카드 형태로 간결하게 표시</p>
            </div>

            <div className="bg-white p-6 sm:p-8 rounded-2xl border border-gray-200 card-hover">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mb-6">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">원문 링크 연동</h3>
              <p className="text-gray-600">상세 확인/신청은 플랫폼의 원본 페이지로 바로 연결</p>
            </div>

            <div className="bg-white p-6 sm:p-8 rounded-2xl border border-gray-200 card-hover">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mb-6">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">간편 사용</h3>
              <p className="text-gray-600">복잡한 회원가입 없이 바로 탐색 가능</p>
            </div>

            <div className="bg-white p-6 sm:p-8 rounded-2xl border border-gray-200 card-hover">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center mb-6">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">안전한 위치 정보</h3>
              <p className="text-gray-600">위치 정보는 앱 사용 중에만 활용되며, 서버에 장기 저장하지 않습니다.</p>
            </div>
          </div>
        </div>
      </section>

      {/* How to Use Section */}
      <section id="how-to-use" className="py-20 bg-gray-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">이렇게 사용해요</h2>
            <p className="text-lg sm:text-xl text-gray-600">간단한 3단계로 체험단을 찾아보세요</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8 animate-fade-in-up">
            <div className="text-center">
              <div className="w-16 h-16 bg-green-600 text-white rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-6">1</div>
              <h3 className="text-xl font-semibold text-gray-900 mb-4">위치 권한 허용</h3>
              <p className="text-gray-600">홈에서 &apos;가까운 체험단 보여주기&apos; 버튼을 눌러 위치 권한을 허용합니다.</p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-green-600 text-white rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-6">2</div>
              <h3 className="text-xl font-semibold text-gray-900 mb-4">지도에서 검색</h3>
              <p className="text-gray-600">지도 화면에서 상단 &apos;이 위치로 검색&apos;을 눌러 현재 화면 범위를 조회합니다.</p>
            </div>

            <div className="text-center">
              <div className="w-16 h-16 bg-green-600 text-white rounded-full flex items-center justify-center text-2xl font-bold mx-auto mb-6">3</div>
              <h3 className="text-xl font-semibold text-gray-900 mb-4">원문 페이지로 이동</h3>
              <p className="text-gray-600">카드/목록에서 원하는 캠페인을 선택하면 원본 페이지로 이동합니다.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Screenshots Section */}
      <section id="screenshots" className="py-20 bg-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold text-gray-900 mb-4">앱 화면 미리보기</h2>
            <p className="text-lg sm:text-xl text-gray-600">리뷰맵의 실제 사용 화면을 확인해보세요</p>
          </div>

          <div className="relative overflow-hidden">
            <div 
              ref={sliderRef}
              className="flex overflow-x-auto scrollbar-hide cursor-grab active:cursor-grabbing"
              onMouseDown={handleMouseDown}
              onMouseLeave={handleMouseLeave}
              onMouseUp={handleMouseUp}
              onMouseMove={handleMouseMove}
              onMouseEnter={handleMouseEnter}
              style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}
            >
              <div className="flex space-x-8 min-w-max">
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-1.png"
                    alt="리뷰맵 앱 화면 1"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-2.png"
                    alt="리뷰맵 앱 화면 2"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-3.png"
                    alt="리뷰맵 앱 화면 3"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-4.png"
                    alt="리뷰맵 앱 화면 4"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-5.png"
                    alt="리뷰맵 앱 화면 5"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                {/* 반복을 위해 다시 추가 */}
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-1.png"
                    alt="리뷰맵 앱 화면 1"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-2.png"
                    alt="리뷰맵 앱 화면 2"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-3.png"
                    alt="리뷰맵 앱 화면 3"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-4.png"
                    alt="리뷰맵 앱 화면 4"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
                <div className="bg-gray-100 rounded-2xl p-4 shadow-lg card-hover">
                  <Image
                    src="/assets/images/app-screenshot-5.png"
                    alt="리뷰맵 앱 화면 5"
                    width={300}
                    height={600}
                    className="w-full h-auto rounded-xl"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-gray-900 text-white py-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid md:grid-cols-3 gap-8">
            <div>
              <div className="flex items-center space-x-3 mb-4">
                <Image
                  src="/assets/images/logo.png"
                  alt="리뷰맵 로고"
                  width={40}
                  height={40}
                  className="w-8 h-8 sm:w-10 sm:h-10"
                />
                <h3 className="text-xl sm:text-2xl font-bold">리뷰맵</h3>
              </div>
              <p className="text-gray-400">내 주변 체험단을 한 번에 찾는 가장 쉬운 방법</p>
            </div>
            
            <div>
              <h4 className="text-lg font-semibold mb-4">링크</h4>
              <ul className="space-y-2">
                <li><Link href="/privacy" className="text-gray-400 hover:text-green-400 transition-colors">개인정보처리방침</Link></li>
                <li><a href="#features" className="text-gray-400 hover:text-green-400 transition-colors">주요 기능</a></li>
                <li><a href="#how-to-use" className="text-gray-400 hover:text-green-400 transition-colors">사용법</a></li>
              </ul>
            </div>
            
            <div>
              <h4 className="text-lg font-semibold mb-4">문의</h4>
              <p className="text-gray-400">앱 관련 문의사항이 있으시면 언제든 연락주세요.</p>
            </div>
          </div>
          
          <div className="border-t border-gray-800 mt-8 pt-8 text-center">
            <p className="text-gray-400">&copy; 2024 리뷰맵. All rights reserved.</p>
          </div>
        </div>
      </footer>
    </div>
  );
}