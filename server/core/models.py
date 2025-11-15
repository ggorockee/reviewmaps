from django.db import models


class CoreModel(models.Model):
    """
    모든 모델의 기본이 되는 추상 모델
    created_at과 updated_at 필드를 제공합니다.
    """
    created_at = models.DateTimeField(
        auto_now_add=True,
        verbose_name="생성일시",
        help_text="레코드가 생성된 시간"
    )
    updated_at = models.DateTimeField(
        auto_now=True,
        verbose_name="수정일시",
        help_text="레코드가 마지막으로 수정된 시간"
    )

    class Meta:
        abstract = True  # 추상 모델로 설정
        ordering = ['-created_at']  # 기본 정렬: 최신순
