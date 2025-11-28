from django.db import models


class Category(models.Model):
    """캠페인 카테고리 모델"""

    name = models.CharField(max_length=100, unique=True, verbose_name="카테고리명")
    display_order = models.IntegerField(default=99, verbose_name="표시 순서")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")

    class Meta:
        db_table = 'categories'
        verbose_name = "카테고리"
        verbose_name_plural = "카테고리"
        ordering = ['display_order', 'id']

    def __str__(self):
        return self.name


class Campaign(models.Model):
    """캠페인 모델"""

    category = models.ForeignKey(
        Category,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='campaigns',
        verbose_name="카테고리"
    )

    # 기본 정보
    platform = models.CharField(max_length=20, verbose_name="플랫폼")
    company = models.CharField(max_length=255, verbose_name="업체명")
    company_link = models.TextField(null=True, blank=True, verbose_name="업체 링크")
    offer = models.TextField(verbose_name="제공 내용")

    # 날짜 정보
    apply_deadline = models.DateTimeField(null=True, blank=True, verbose_name="신청 마감일")
    review_deadline = models.DateTimeField(null=True, blank=True, verbose_name="리뷰 마감일")
    apply_from = models.DateTimeField(null=True, blank=True, verbose_name="신청 시작일")

    # 위치 정보
    address = models.TextField(null=True, blank=True, verbose_name="주소")
    lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, verbose_name="위도")
    lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, verbose_name="경도")

    # 이미지 및 링크
    img_url = models.TextField(null=True, blank=True, verbose_name="이미지 URL")
    content_link = models.TextField(null=True, blank=True, verbose_name="콘텐츠 링크")

    # 검색 및 분류
    search_text = models.CharField(max_length=20, null=True, blank=True, verbose_name="검색 텍스트")
    source = models.CharField(max_length=100, null=True, blank=True, verbose_name="출처")
    title = models.TextField(null=True, blank=True, verbose_name="제목")
    campaign_type = models.CharField(max_length=50, null=True, blank=True, verbose_name="캠페인 유형")
    region = models.CharField(max_length=100, null=True, blank=True, verbose_name="지역")
    campaign_channel = models.CharField(max_length=255, null=True, blank=True, verbose_name="캠페인 채널")

    # 프로모션
    promotion_level = models.IntegerField(default=0, verbose_name="프로모션 레벨")

    # 타임스탬프
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="수정일시")

    class Meta:
        db_table = 'campaign'
        verbose_name = "캠페인"
        verbose_name_plural = "캠페인"
        ordering = ['-created_at']
        indexes = [
            # 추천 캠페인 API 최적화 (가장 중요)
            # promotion_level DESC + apply_deadline >= NOW() + 지도 뷰포트(lat/lng) 필터링
            # 사용: 캠페인 목록 조회 시 프로모션 우선순위 정렬 + 마감일 필터 + 위치 기반 검색
            models.Index(
                fields=['promotion_level', 'apply_deadline', 'lat', 'lng'],
                name='idx_cpg_promo_ddl_loc'
            ),

            # 기본 정렬 최적화
            # 사용: 기본 캠페인 목록 조회 (최신순)
            models.Index(fields=['-created_at'], name='idx_cpg_created'),

            # 카테고리 필터링 최적화
            # 사용: 특정 카테고리의 캠페인 조회
            models.Index(fields=['category'], name='idx_cpg_category'),

            # 마감일 필터링 최적화
            # 사용: 마감임박, 진행중 캠페인 필터링
            models.Index(fields=['apply_deadline'], name='idx_cpg_deadline'),

            # 지역 검색 최적화 (추가)
            # 사용: 지역별 캠페인 필터링
            models.Index(fields=['region'], name='idx_cpg_region'),

            # 캠페인 유형 필터링 최적화 (추가)
            # 사용: 유형별 캠페인 필터링 (방문형, 배송형 등)
            models.Index(fields=['campaign_type'], name='idx_cpg_type'),

            # 가까운 체험단 API 최적화 (거리 기반 조회)
            # 사용: lat/lng 기반 거리 정렬 쿼리 성능 향상
            models.Index(
                fields=['lat', 'lng', 'apply_deadline'],
                name='idx_cpg_location_deadline'
            ),

            # 복합 인덱스: 프로모션 + 생성일 (추천 정렬용)
            models.Index(
                fields=['-promotion_level', '-created_at'],
                name='idx_cpg_promo_created'
            ),
        ]

    def __str__(self):
        return f"{self.company} - {self.offer[:50]}"


class RawCategory(models.Model):
    """원본 카테고리 모델"""

    raw_text = models.TextField(unique=True, verbose_name="원본 텍스트")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="생성일시")

    class Meta:
        db_table = 'raw_categories'
        verbose_name = "원본 카테고리"
        verbose_name_plural = "원본 카테고리"

    def __str__(self):
        return self.raw_text


class CategoryMapping(models.Model):
    """카테고리 매핑 모델"""

    raw_category = models.OneToOneField(
        RawCategory,
        on_delete=models.CASCADE,
        verbose_name="원본 카테고리"
    )
    standard_category = models.ForeignKey(
        Category,
        on_delete=models.CASCADE,
        verbose_name="표준 카테고리"
    )

    class Meta:
        db_table = 'category_mappings'
        verbose_name = "카테고리 매핑"
        verbose_name_plural = "카테고리 매핑"

    def __str__(self):
        return f"{self.raw_category.raw_text} -> {self.standard_category.name}"
