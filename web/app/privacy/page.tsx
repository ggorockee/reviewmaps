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
                  <li>• <strong>계정정보</strong>: 이름, 이메일 주소, 사용자 ID (로그인 시)</li>
                  <li>• <strong>위치정보</strong>: 앱 사용 중 현재 위치 (GPS, 네트워크 기반 위치)</li>
                  <li>• <strong>기기정보</strong>: 기기 식별자, OS 버전, 앱 버전</li>
                  <li>• <strong>사용 통계</strong>: 앱 사용 패턴, 기능 이용 현황, 검색 기록</li>
                </ul>
              </div>
              
              <div className="bg-green-50 p-6 rounded-xl">
                <h3 className="text-lg font-semibold text-green-900 mb-2">이용 목적</h3>
                <ul className="text-gray-700 space-y-2">
                  <li>• 회원 가입, 로그인 및 계정 관리</li>
                  <li>• 사용자 주변 체험단 정보 제공</li>
                  <li>• 지도 서비스 및 위치 기반 검색 기능 제공</li>
                  <li>• 맞춤형 서비스 제공 및 사용자 경험 향상</li>
                  <li>• 앱 성능 개선 및 분석</li>
                  <li>• 광고 서비스 제공 (AdMob)</li>
                  <li>• 비밀번호 재설정 등 계정 관련 안내</li>
                </ul>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">2. 개인정보 보관 및 처리</h2>
              <div className="bg-yellow-50 p-6 rounded-xl">
                <h3 className="text-lg font-semibold text-yellow-900 mb-2">보관 및 처리 안내</h3>
                <ul className="text-gray-700 space-y-2">
                  <li>• <strong>계정정보</strong>: 회원 탈퇴 시까지 보관하며, 탈퇴 후 즉시 삭제됩니다.</li>
                  <li>• <strong>위치정보</strong>: 앱 사용 중에만 수집되며, 서버에 장기 저장하지 않습니다.</li>
                  <li>• <strong>법적 의무</strong>: 관련 법령에 따라 일부 정보는 30일간 보관될 수 있습니다.</li>
                  <li>• 수집된 정보는 <strong>HTTPS 암호화 통신</strong>과 <strong>Firebase 보안</strong>을 통해 안전하게 처리됩니다.</li>
                  <li>• 계정 삭제 시 관련 데이터는 7일 이내에 완전히 삭제됩니다.</li>
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
                  이용자는 개인정보 보호법에 따라 다음과 같은 권리를 가집니다:
                </p>
                <ul className="text-gray-700 space-y-2">
                  <li>• <strong>개인정보 열람</strong>: 앱 내 프로필 화면에서 본인의 정보를 확인할 수 있습니다.</li>
                  <li>• <strong>개인정보 수정</strong>: 앱 내 프로필 화면에서 정보를 수정할 수 있습니다.</li>
                  <li>• <strong>계정 삭제</strong>: 앱 내 설정 또는 이메일로 계정 삭제를 요청할 수 있습니다.</li>
                  <li>• <strong>위치정보 수집 거부</strong>: 앱 설정에서 위치 권한을 거부할 수 있습니다.</li>
                  <li>• <strong>광고 식별자 재설정</strong>: 기기 설정에서 광고 ID를 재설정할 수 있습니다.</li>
                </ul>
              </div>
            </section>

            <section id="account-deletion" className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">6. 계정 및 데이터 삭제</h2>
              <div className="bg-red-50 p-6 rounded-xl mb-4">
                <h3 className="text-lg font-semibold text-red-900 mb-3">리뷰맵 - 계정 삭제 안내</h3>
                <p className="text-gray-700 mb-3">
                  <strong>개발자:</strong> WooHyeon Kim
                </p>
                
                <h4 className="text-base font-semibold text-red-800 mb-2 mt-4">계정 삭제 방법</h4>
                <div className="space-y-3">
                  <div className="bg-white p-4 rounded-lg">
                    <p className="font-semibold text-gray-900 mb-2">1. 앱 내에서 직접 삭제</p>
                    <ul className="text-gray-700 space-y-1 ml-4">
                      <li>• 리뷰맵 앱 실행</li>
                      <li>• 프로필 화면 이동</li>
                      <li>• 설정 메뉴 선택</li>
                      <li>• &apos;계정 삭제&apos; 버튼 클릭</li>
                    </ul>
                  </div>
                  
                  <div className="bg-white p-4 rounded-lg">
                    <p className="font-semibold text-gray-900 mb-2">2. 이메일로 삭제 요청</p>
                    <ul className="text-gray-700 space-y-1 ml-4">
                      <li>• 이메일: <a href="mailto:woohaen88@gmail.com" className="text-blue-600 hover:underline">woohaen88@gmail.com</a></li>
                      <li>• 제목: [리뷰맵] 계정 삭제 요청</li>
                      <li>• 내용: 가입 이메일 주소와 계정 삭제 요청 명시</li>
                    </ul>
                  </div>
                </div>
                
                <h4 className="text-base font-semibold text-red-800 mb-2 mt-4">삭제되는 데이터</h4>
                <ul className="text-gray-700 space-y-1">
                  <li>• 사용자 계정 정보 (이름, 이메일)</li>
                  <li>• 검색 기록</li>
                  <li>• 앱 설정 및 환경설정</li>
                  <li>• 사용자가 작성한 리뷰 (있는 경우)</li>
                </ul>
                
                <h4 className="text-base font-semibold text-red-800 mb-2 mt-4">보관되는 데이터</h4>
                <p className="text-gray-700">
                  법적 의무 준수를 위해 다음 데이터는 30일간 보관됩니다:
                </p>
                <ul className="text-gray-700 space-y-1 mt-2">
                  <li>• 법적 요구사항에 따른 최소한의 정보</li>
                  <li>• 익명화된 통계 데이터</li>
                </ul>
                
                <h4 className="text-base font-semibold text-red-800 mb-2 mt-4">처리 기간</h4>
                <p className="text-gray-700">
                  계정 삭제 요청 후 <strong className="text-red-700">7일 이내</strong>에 처리됩니다.
                </p>
                
                <div className="bg-gray-100 p-4 rounded-lg mt-4">
                  <h4 className="text-base font-semibold text-gray-900 mb-2">연락처</h4>
                  <ul className="text-gray-700 space-y-1">
                    <li>• 이메일: <a href="mailto:woohaen88@gmail.com" className="text-blue-600 hover:underline">woohaen88@gmail.com</a></li>
                    <li>• 앱 이름: 리뷰맵</li>
                    <li>• 개발자: WooHyeon Kim</li>
                  </ul>
                </div>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">7. 쿠키 및 추적 기술</h2>
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
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">8. 개인정보처리방침 변경</h2>
              <div className="bg-gray-50 p-6 rounded-xl">
                <p className="text-gray-700">
                  이 개인정보처리방침은 법령, 정책 또는 보안기술의 변경에 따라 내용의 추가, 삭제 및 수정이 있을 시에는 
                  개정 최소 7일 전부터 앱 내 공지사항을 통해 고지할 것입니다.
                </p>
                <p className="text-gray-600 mt-4">
                  <strong>최종 수정일:</strong> 2024년 11월 27일
                </p>
              </div>
            </section>

            <section className="mb-8">
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">9. 문의처</h2>
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
