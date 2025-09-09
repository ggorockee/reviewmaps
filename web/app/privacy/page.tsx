import Link from "next/link";
import Image from "next/image";

export default function Privacy() {
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
                className="w-10 h-10"
              />
              <h1 className="text-2xl font-bold text-gray-900">리뷰맵</h1>
            </Link>
            <Link href="/" className="text-green-600 hover:text-green-700 font-medium">
              홈으로 돌아가기
            </Link>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="bg-white rounded-2xl shadow-lg p-8 md:p-12">
          <h1 className="text-4xl font-bold text-gray-900 mb-8">개인정보처리방침</h1>
          
          <div className="prose prose-lg max-w-none">
            <p className="text-gray-600 mb-8">
              리뷰맵은 이용자의 개인정보 보호를 매우 중요하게 생각하며, 「개인정보 보호법」 및 관련 법령에 따라 개인정보를 안전하게 처리하고 있습니다.
            </p>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">1. 개인정보 수집 및 이용</h2>
              <div className="bg-blue-50 p-6 rounded-xl mb-4">
                <h3 className="text-lg font-semibold text-blue-900 mb-2">수집하는 개인정보</h3>
                <ul className="text-gray-700 space-y-2">
                  <li>• <strong>위치정보</strong>: 앱 사용 중 현재 위치 (GPS, 네트워크 기반 위치)</li>
                  <li>• <strong>기기정보</strong>: 기기 식별자, OS 버전, 앱 버전</li>
                  <li>• <strong>사용 통계</strong>: 앱 사용 패턴, 기능 이용 현황</li>
                </ul>
              </div>
              
              <div className="bg-green-50 p-6 rounded-xl">
                <h3 className="text-lg font-semibold text-green-900 mb-2">이용 목적</h3>
                <ul className="text-gray-700 space-y-2">
                  <li>• 사용자 주변 체험단 정보 제공</li>
                  <li>• 지도 서비스 및 위치 기반 검색 기능 제공</li>
                  <li>• 앱 성능 개선 및 사용자 경험 향상</li>
                  <li>• 광고 서비스 제공 (AdMob)</li>
                </ul>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">2. 개인정보 보관 및 처리</h2>
              <div className="bg-yellow-50 p-6 rounded-xl">
                <h3 className="text-lg font-semibold text-yellow-900 mb-2">중요한 안내사항</h3>
                <ul className="text-gray-700 space-y-2">
                  <li>• <strong>위치정보는 앱 사용 중에만 수집</strong>되며, 서버에 장기 저장하지 않습니다.</li>
                  <li>• <strong>회원가입이 없으므로</strong> 개인 식별 정보(이름, 이메일, 전화번호 등)를 수집하지 않습니다.</li>
                  <li>• 수집된 정보는 <strong>Firebase</strong>를 통해 안전하게 처리됩니다.</li>
                  <li>• 앱 삭제 시 관련 데이터는 자동으로 삭제됩니다.</li>
                </ul>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">3. 제3자 제공 및 공유</h2>
              <div className="bg-red-50 p-6 rounded-xl">
                <h3 className="text-lg font-semibold text-red-900 mb-2">제3자 제공 현황</h3>
                <ul className="text-gray-700 space-y-2">
                  <li>• <strong>Google AdMob</strong>: 광고 서비스 제공을 위한 광고 식별자 수집</li>
                  <li>• <strong>Firebase (Google)</strong>: 앱 분석 및 크래시 리포트 수집</li>
                  <li>• <strong>네이버 지도 SDK</strong>: 지도 서비스 제공을 위한 위치정보 처리</li>
                </ul>
                <p className="text-gray-600 mt-4">
                  위 제3자들은 각각의 개인정보처리방침에 따라 정보를 처리하며, 
                  리뷰맵은 이용자의 개인정보를 영리 목적으로 제3자에게 판매하거나 제공하지 않습니다.
                </p>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">4. 개인정보 보호 조치</h2>
              <div className="grid md:grid-cols-2 gap-6">
                <div className="bg-gray-50 p-6 rounded-xl">
                  <h3 className="text-lg font-semibold text-gray-900 mb-3">기술적 보호조치</h3>
                  <ul className="text-gray-700 space-y-2">
                    <li>• 데이터 암호화 전송 (HTTPS)</li>
                    <li>• Firebase 보안 규칙 적용</li>
                    <li>• 정기적인 보안 업데이트</li>
                  </ul>
                </div>
                <div className="bg-gray-50 p-6 rounded-xl">
                  <h3 className="text-lg font-semibold text-gray-900 mb-3">관리적 보호조치</h3>
                  <ul className="text-gray-700 space-y-2">
                    <li>• 최소한의 정보 수집 원칙</li>
                    <li>• 정기적인 개인정보 처리 현황 점검</li>
                    <li>• 개인정보 보호 교육 실시</li>
                  </ul>
                </div>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">5. 이용자 권리</h2>
              <div className="bg-purple-50 p-6 rounded-xl">
                <p className="text-gray-700 mb-4">
                  리뷰맵은 회원가입이 없는 서비스이므로, 개인정보 수집이 최소화되어 있습니다. 
                  하지만 이용자는 다음과 같은 권리를 가집니다:
                </p>
                <ul className="text-gray-700 space-y-2">
                  <li>• <strong>위치정보 수집 거부</strong>: 앱 설정에서 위치 권한을 거부할 수 있습니다.</li>
                  <li>• <strong>광고 식별자 재설정</strong>: 기기 설정에서 광고 ID를 재설정할 수 있습니다.</li>
                  <li>• <strong>앱 삭제</strong>: 앱을 삭제하면 관련 데이터가 자동으로 삭제됩니다.</li>
                </ul>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">6. 쿠키 및 추적 기술</h2>
              <div className="bg-indigo-50 p-6 rounded-xl">
                <p className="text-gray-700 mb-4">
                  리뷰맵은 다음과 같은 기술을 사용하여 서비스를 제공합니다:
                </p>
                <ul className="text-gray-700 space-y-2">
                  <li>• <strong>Firebase Analytics</strong>: 앱 사용 통계 수집</li>
                  <li>• <strong>Google AdMob</strong>: 맞춤형 광고 제공</li>
                  <li>• <strong>네이버 지도 SDK</strong>: 위치 기반 지도 서비스</li>
                </ul>
                <p className="text-gray-600 mt-4">
                  이러한 기술들은 개인을 식별할 수 없는 익명화된 정보만을 수집합니다.
                </p>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">7. 개인정보처리방침 변경</h2>
              <div className="bg-gray-50 p-6 rounded-xl">
                <p className="text-gray-700">
                  이 개인정보처리방침은 법령, 정책 또는 보안기술의 변경에 따라 내용의 추가, 삭제 및 수정이 있을 시에는 
                  개정 최소 7일 전부터 앱 내 공지사항을 통해 고지할 것입니다.
                </p>
                <p className="text-gray-600 mt-4">
                  <strong>최종 수정일:</strong> 2024년 12월 19일
                </p>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">8. 문의처</h2>
              <div className="bg-blue-50 p-6 rounded-xl">
                <p className="text-gray-700 mb-4">
                  개인정보 처리에 관한 문의사항이 있으시면 언제든 연락주시기 바랍니다.
                </p>
                <div className="text-gray-700">
                  <p><strong>서비스명:</strong> 리뷰맵</p>
                  <p><strong>개인정보보호책임자:</strong> 리뷰맵 개발팀</p>
                  <p><strong>연락처:</strong> 앱 내 문의하기 기능을 통해 연락 가능</p>
                </div>
              </div>
            </section>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-gray-900 text-white py-8">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <div className="flex items-center justify-center space-x-3 mb-4">
            <Image
              src="/assets/images/logo.png"
              alt="리뷰맵 로고"
              width={32}
              height={32}
              className="w-8 h-8"
            />
            <h3 className="text-xl font-bold">리뷰맵</h3>
          </div>
          <p className="text-gray-400">&copy; 2024 리뷰맵. All rights reserved.</p>
        </div>
      </footer>
    </div>
  );
}
