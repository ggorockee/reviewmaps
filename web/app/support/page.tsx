'use client';

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";

export default function SupportPage() {
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    device: '',
    appVersion: '',
    subject: '',
    message: '',
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitStatus, setSubmitStatus] = useState<'idle' | 'success' | 'error'>('idle');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);

    try {
      // 이메일 클라이언트로 전송하기 위한 mailto 링크 생성
      const subject = encodeURIComponent(`[리뷰맵 문의] ${formData.subject}`);
      const body = encodeURIComponent(
        `이름: ${formData.name}\n` +
        `이메일: ${formData.email}\n` +
        `기기: ${formData.device}\n` +
        `앱 버전: ${formData.appVersion}\n\n` +
        `문의 내용:\n${formData.message}`
      );

      window.location.href = `mailto:woohaen88@gmail.com?subject=${subject}&body=${body}`;

      setSubmitStatus('success');
      setFormData({
        name: '',
        email: '',
        device: '',
        appVersion: '',
        subject: '',
        message: '',
      });
    } catch (error) {
      console.error('Submit error:', error);
      setSubmitStatus('error');
    } finally {
      setIsSubmitting(false);
      setTimeout(() => setSubmitStatus('idle'), 5000);
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
  };

  return (
    <div className="min-h-screen bg-white">
      {/* Header */}
      <header className="bg-white/80 backdrop-blur-sm shadow-sm sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <Link href="/" className="flex items-center space-x-3">
              <Image
                src="/assets/images/logo.png"
                alt="리뷰맵 로고"
                width={40}
                height={40}
                className="w-8 h-8 sm:w-10 sm:h-10"
              />
              <h1 className="text-xl sm:text-2xl font-bold text-gray-900">리뷰맵</h1>
            </Link>
            <nav className="hidden md:flex space-x-8">
              <Link href="/#features" className="text-gray-600 hover:text-green-600 transition-colors">주요 기능</Link>
              <Link href="/#how-to-use" className="text-gray-600 hover:text-green-600 transition-colors">사용법</Link>
              <Link href="/#screenshots" className="text-gray-600 hover:text-green-600 transition-colors">앱 화면</Link>
              <Link href="/privacy" className="text-gray-600 hover:text-green-600 transition-colors">개인정보처리방침</Link>
              <Link href="/support" className="text-green-600 font-semibold">고객지원</Link>
            </nav>
          </div>
        </div>
      </header>

      {/* Support Content */}
      <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <h1 className="text-4xl font-bold text-gray-900 mb-8">고객 지원</h1>

        {/* App Info Section */}
        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">앱 정보</h2>
          <div className="bg-blue-50 p-6 rounded-xl">
            <ul className="text-gray-700 space-y-2">
              <li>• <strong>앱 이름</strong>: 리뷰맵</li>
              <li>• <strong>개발자</strong>: WooHyeon Kim</li>
              <li>• <strong>버전</strong>: 2.0.8</li>
              <li>• <strong>설명</strong>: 내 주변 체험단을 지도와 리스트로 한 번에 보여주는 앱</li>
            </ul>
          </div>
        </section>

        {/* FAQ Section */}
        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">자주 묻는 질문</h2>
          <div className="space-y-4">
            <details className="bg-gray-50 p-6 rounded-xl">
              <summary className="cursor-pointer font-semibold text-gray-900">Q. 앱은 어떻게 사용하나요?</summary>
              <p className="mt-3 text-gray-700">
                1. 위치 권한을 허용하여 내 주변 체험단을 확인합니다.<br />
                2. 지도를 드래그하고 &quot;이 위치로 검색&quot;을 눌러 원하는 지역의 체험단을 찾습니다.<br />
                3. 카드를 선택하여 원본 페이지로 이동하여 신청합니다.
              </p>
            </details>

            <details className="bg-gray-50 p-6 rounded-xl">
              <summary className="cursor-pointer font-semibold text-gray-900">Q. 위치 정보는 안전한가요?</summary>
              <p className="mt-3 text-gray-700">
                네, 위치 정보는 앱 사용 중에만 활용되며 서버에 장기 저장하지 않습니다. 사용자의 프라이버시를 최우선으로 보호합니다.
              </p>
            </details>

            <details className="bg-gray-50 p-6 rounded-xl">
              <summary className="cursor-pointer font-semibold text-gray-900">Q. 회원가입이 필요한가요?</summary>
              <p className="mt-3 text-gray-700">
                기본 체험단 검색은 회원가입 없이 사용 가능합니다. 키워드 알림 등 일부 기능은 로그인이 필요합니다.
              </p>
            </details>

            <details className="bg-gray-50 p-6 rounded-xl">
              <summary className="cursor-pointer font-semibold text-gray-900">Q. 어떤 체험단 플랫폼을 지원하나요?</summary>
              <p className="mt-3 text-gray-700">
                리뷰노트, 인플랙서, 레뷰, 체험단닷컴 등 주요 체험단 플랫폼의 정보를 통합하여 제공합니다.
              </p>
            </details>

            <details className="bg-gray-50 p-6 rounded-xl">
              <summary className="cursor-pointer font-semibold text-gray-900">Q. 로그인에 문제가 있어요</summary>
              <p className="mt-3 text-gray-700">
                카카오, Google, Apple 계정으로 로그인할 수 있습니다. 로그인 오류가 계속되면 아래 문의 양식을 통해 연락주세요.
                기기 정보(iPad/iPhone 등), 앱 버전, 사용 중인 로그인 방법(Apple/Kakao/Google)을 함께 알려주시면 빠르게 도와드리겠습니다.
              </p>
            </details>
          </div>
        </section>

        {/* Contact Form Section */}
        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">문의하기</h2>
          <div className="bg-gray-50 p-6 rounded-xl">
            <p className="text-gray-700 mb-6">
              앱 사용 중 문제가 발생하거나 궁금한 점이 있으시면 아래 양식을 작성해주세요.
            </p>

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label htmlFor="name" className="block text-sm font-medium text-gray-700 mb-1">
                  이름 *
                </label>
                <input
                  type="text"
                  id="name"
                  name="name"
                  required
                  value={formData.name}
                  onChange={handleChange}
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
                  placeholder="홍길동"
                />
              </div>

              <div>
                <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
                  이메일 *
                </label>
                <input
                  type="email"
                  id="email"
                  name="email"
                  required
                  value={formData.email}
                  onChange={handleChange}
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
                  placeholder="your@email.com"
                />
              </div>

              <div>
                <label htmlFor="device" className="block text-sm font-medium text-gray-700 mb-1">
                  기기 정보 (예: iPhone 15, iPad Air 11-inch)
                </label>
                <input
                  type="text"
                  id="device"
                  name="device"
                  value={formData.device}
                  onChange={handleChange}
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
                  placeholder="iPhone 15 Pro"
                />
              </div>

              <div>
                <label htmlFor="appVersion" className="block text-sm font-medium text-gray-700 mb-1">
                  앱 버전 (설정에서 확인 가능)
                </label>
                <input
                  type="text"
                  id="appVersion"
                  name="appVersion"
                  value={formData.appVersion}
                  onChange={handleChange}
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
                  placeholder="2.0.8"
                />
              </div>

              <div>
                <label htmlFor="subject" className="block text-sm font-medium text-gray-700 mb-1">
                  제목 *
                </label>
                <input
                  type="text"
                  id="subject"
                  name="subject"
                  required
                  value={formData.subject}
                  onChange={handleChange}
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent"
                  placeholder="문의 제목을 입력하세요"
                />
              </div>

              <div>
                <label htmlFor="message" className="block text-sm font-medium text-gray-700 mb-1">
                  내용 *
                </label>
                <textarea
                  id="message"
                  name="message"
                  required
                  value={formData.message}
                  onChange={handleChange}
                  rows={6}
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-green-500 focus:border-transparent resize-none"
                  placeholder="문의 내용을 자세히 입력해주세요"
                />
              </div>

              <button
                type="submit"
                disabled={isSubmitting}
                className="w-full bg-green-600 text-white py-3 px-6 rounded-lg font-semibold hover:bg-green-700 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed"
              >
                {isSubmitting ? '전송 중...' : '문의하기'}
              </button>

              {submitStatus === 'success' && (
                <div className="p-4 bg-green-50 text-green-800 rounded-lg">
                  이메일 클라이언트가 열립니다. 메일을 확인하고 전송해주세요.
                </div>
              )}

              {submitStatus === 'error' && (
                <div className="p-4 bg-red-50 text-red-800 rounded-lg">
                  오류가 발생했습니다. woohaen88@gmail.com으로 직접 이메일을 보내주세요.
                </div>
              )}
            </form>

            <div className="mt-6 pt-6 border-t border-gray-200">
              <p className="text-sm text-gray-600">
                <strong>직접 문의:</strong> <a href="mailto:woohaen88@gmail.com" className="text-green-600 hover:underline">woohaen88@gmail.com</a>
              </p>
            </div>
          </div>
        </section>

        {/* Additional Info */}
        <section className="mb-8">
          <h2 className="text-2xl font-semibold text-gray-900 mb-4">관련 링크</h2>
          <div className="bg-gray-50 p-6 rounded-xl space-y-3">
            <div>
              <Link href="/privacy" className="text-green-600 hover:underline font-medium">
                📄 개인정보처리방침
              </Link>
              <p className="text-sm text-gray-600 mt-1">리뷰맵의 개인정보 처리 방침을 확인하세요</p>
            </div>
            <div>
              <a
                href="https://play.google.com/store/apps/details?id=com.reviewmaps.mobile"
                target="_blank"
                rel="noopener noreferrer"
                className="text-green-600 hover:underline font-medium"
              >
                📱 Google Play 스토어
              </a>
              <p className="text-sm text-gray-600 mt-1">Android 앱 다운로드</p>
            </div>
            <div>
              <a
                href="https://apps.apple.com/us/app/%EB%A6%AC%EB%B7%B0%EB%A7%B5/id6751343880"
                target="_blank"
                rel="noopener noreferrer"
                className="text-green-600 hover:underline font-medium"
              >
                🍎 App Store
              </a>
              <p className="text-sm text-gray-600 mt-1">iOS 앱 다운로드</p>
            </div>
          </div>
        </section>
      </main>

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
                <li><Link href="/support" className="text-gray-400 hover:text-green-400 transition-colors">고객지원</Link></li>
                <li><Link href="/#features" className="text-gray-400 hover:text-green-400 transition-colors">주요 기능</Link></li>
                <li><Link href="/#how-to-use" className="text-gray-400 hover:text-green-400 transition-colors">사용법</Link></li>
              </ul>
            </div>

            <div>
              <h4 className="text-lg font-semibold mb-4">문의</h4>
              <p className="text-gray-400 mb-2">앱 관련 문의사항이 있으시면 언제든 연락주세요.</p>
              <a href="mailto:woohaen88@gmail.com" className="text-green-400 hover:text-green-300">
                woohaen88@gmail.com
              </a>
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
