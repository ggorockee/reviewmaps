"""
app_config 유틸리티 함수
버전 비교 및 기타 헬퍼 함수
"""
from typing import Tuple


class Version:
    """
    Semantic Versioning (major.minor.patch) 버전 비교 클래스

    Examples:
        >>> v1 = Version("1.3.0")
        >>> v2 = Version("1.4.0")
        >>> v1 < v2
        True
        >>> v1 == Version("1.3.0")
        True
    """

    def __init__(self, version_string: str):
        """
        Args:
            version_string: 버전 문자열 (예: "1.3.5")

        Raises:
            ValueError: 잘못된 버전 형식인 경우
        """
        self.version_string = version_string
        self.major, self.minor, self.patch = self._parse_version(version_string)

    def _parse_version(self, version_string: str) -> Tuple[int, int, int]:
        """
        버전 문자열을 major, minor, patch로 파싱

        Args:
            version_string: 버전 문자열 (예: "1.3.5")

        Returns:
            (major, minor, patch) tuple

        Raises:
            ValueError: 잘못된 버전 형식인 경우
        """
        if not version_string:
            raise ValueError("버전 문자열이 비어있습니다")

        try:
            parts = version_string.strip().split('.')
            if len(parts) != 3:
                raise ValueError(f"버전 형식이 잘못되었습니다: {version_string}")

            major, minor, patch = [int(p) for p in parts]

            if major < 0 or minor < 0 or patch < 0:
                raise ValueError("버전 번호는 음수일 수 없습니다")

            return (major, minor, patch)
        except (ValueError, AttributeError) as e:
            raise ValueError(f"잘못된 버전 형식: {version_string}") from e

    def __eq__(self, other) -> bool:
        """동일 버전 비교"""
        if not isinstance(other, Version):
            return False
        return (self.major, self.minor, self.patch) == (other.major, other.minor, other.patch)

    def __lt__(self, other) -> bool:
        """버전이 낮은지 비교"""
        if not isinstance(other, Version):
            return NotImplemented
        return (self.major, self.minor, self.patch) < (other.major, other.minor, other.patch)

    def __le__(self, other) -> bool:
        """버전이 같거나 낮은지 비교"""
        return self == other or self < other

    def __gt__(self, other) -> bool:
        """버전이 높은지 비교"""
        if not isinstance(other, Version):
            return NotImplemented
        return (self.major, self.minor, self.patch) > (other.major, other.minor, other.patch)

    def __ge__(self, other) -> bool:
        """버전이 같거나 높은지 비교"""
        return self == other or self > other

    def __str__(self) -> str:
        return self.version_string

    def __repr__(self) -> str:
        return f"Version('{self.version_string}')"


def compare_versions(current: str, target: str) -> int:
    """
    두 버전을 비교하는 헬퍼 함수

    Args:
        current: 현재 버전 문자열
        target: 비교할 버전 문자열

    Returns:
        -1: current < target (업데이트 필요)
        0: current == target (동일 버전)
        1: current > target (최신 버전)

    Examples:
        >>> compare_versions("1.3.0", "1.4.0")
        -1
        >>> compare_versions("1.4.0", "1.4.0")
        0
        >>> compare_versions("1.5.0", "1.4.0")
        1
    """
    v_current = Version(current)
    v_target = Version(target)

    if v_current < v_target:
        return -1
    elif v_current == v_target:
        return 0
    else:
        return 1


def needs_update(current: str, latest: str) -> bool:
    """
    업데이트가 필요한지 확인

    Args:
        current: 현재 앱 버전
        latest: 최신 버전

    Returns:
        업데이트 필요 여부
    """
    return compare_versions(current, latest) < 0


def is_force_update_required(current: str, minimum: str) -> bool:
    """
    강제 업데이트가 필요한지 확인

    Args:
        current: 현재 앱 버전
        minimum: 최소 지원 버전

    Returns:
        강제 업데이트 필요 여부 (current < minimum)
    """
    return compare_versions(current, minimum) < 0
