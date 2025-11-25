"""
app_config.utils 테스트
버전 비교 유틸리티 함수 테스트
"""
import pytest
from app_config.utils import (
    Version,
    compare_versions,
    needs_update,
    is_force_update_required,
)


class TestVersionClass:
    """Version 클래스 테스트"""

    def test_version_parsing_valid(self):
        """정상적인 버전 문자열 파싱"""
        v = Version("1.3.5")
        assert v.major == 1
        assert v.minor == 3
        assert v.patch == 5
        assert str(v) == "1.3.5"

    def test_version_parsing_with_spaces(self):
        """공백이 있는 버전 문자열 파싱"""
        v = Version(" 1.3.5 ")
        assert v.major == 1
        assert v.minor == 3
        assert v.patch == 5

    def test_version_parsing_invalid_format(self):
        """잘못된 형식의 버전 문자열"""
        with pytest.raises(ValueError, match="잘못된 버전 형식"):
            Version("1.3")

        with pytest.raises(ValueError, match="잘못된 버전 형식"):
            Version("1.3.5.6")

    def test_version_parsing_non_numeric(self):
        """숫자가 아닌 버전 문자열"""
        with pytest.raises(ValueError, match="잘못된 버전 형식"):
            Version("1.3.a")

    def test_version_parsing_negative_numbers(self):
        """음수 버전 번호"""
        with pytest.raises(ValueError, match="잘못된 버전 형식"):
            Version("1.-3.5")

    def test_version_parsing_empty(self):
        """빈 문자열"""
        with pytest.raises(ValueError, match="버전 문자열이 비어있습니다"):
            Version("")

    def test_version_equality(self):
        """버전 동일성 비교"""
        v1 = Version("1.3.5")
        v2 = Version("1.3.5")
        v3 = Version("1.3.6")

        assert v1 == v2
        assert v1 != v3
        assert not (v1 == v3)

    def test_version_less_than(self):
        """버전 미만 비교"""
        v1 = Version("1.3.5")
        v2 = Version("1.4.0")
        v3 = Version("2.0.0")

        assert v1 < v2
        assert v1 < v3
        assert v2 < v3
        assert not (v2 < v1)

    def test_version_less_than_or_equal(self):
        """버전 이하 비교"""
        v1 = Version("1.3.5")
        v2 = Version("1.3.5")
        v3 = Version("1.4.0")

        assert v1 <= v2
        assert v1 <= v3
        assert not (v3 <= v1)

    def test_version_greater_than(self):
        """버전 초과 비교"""
        v1 = Version("2.0.0")
        v2 = Version("1.4.0")
        v3 = Version("1.3.5")

        assert v1 > v2
        assert v1 > v3
        assert v2 > v3
        assert not (v2 > v1)

    def test_version_greater_than_or_equal(self):
        """버전 이상 비교"""
        v1 = Version("1.4.0")
        v2 = Version("1.4.0")
        v3 = Version("1.3.5")

        assert v1 >= v2
        assert v1 >= v3
        assert not (v3 >= v1)

    def test_version_comparison_across_major_minor_patch(self):
        """major, minor, patch 전체 비교"""
        # Major 버전 차이
        assert Version("2.0.0") > Version("1.9.9")

        # Minor 버전 차이
        assert Version("1.5.0") > Version("1.4.9")

        # Patch 버전 차이
        assert Version("1.3.6") > Version("1.3.5")

        # 동일 버전
        assert Version("1.3.5") == Version("1.3.5")

    def test_version_repr(self):
        """Version 객체 표현"""
        v = Version("1.3.5")
        assert repr(v) == "Version('1.3.5')"


class TestCompareVersionsFunction:
    """compare_versions 함수 테스트"""

    def test_compare_versions_less_than(self):
        """현재 버전이 더 낮은 경우"""
        assert compare_versions("1.3.0", "1.4.0") == -1
        assert compare_versions("1.3.5", "2.0.0") == -1
        assert compare_versions("1.3.5", "1.3.6") == -1

    def test_compare_versions_equal(self):
        """버전이 동일한 경우"""
        assert compare_versions("1.3.5", "1.3.5") == 0
        assert compare_versions("2.0.0", "2.0.0") == 0

    def test_compare_versions_greater_than(self):
        """현재 버전이 더 높은 경우"""
        assert compare_versions("1.4.0", "1.3.0") == 1
        assert compare_versions("2.0.0", "1.9.9") == 1
        assert compare_versions("1.3.6", "1.3.5") == 1


class TestNeedsUpdateFunction:
    """needs_update 함수 테스트"""

    def test_needs_update_true(self):
        """업데이트가 필요한 경우"""
        assert needs_update("1.3.0", "1.4.0") is True
        assert needs_update("1.3.5", "2.0.0") is True
        assert needs_update("1.3.5", "1.3.6") is True

    def test_needs_update_false(self):
        """업데이트가 불필요한 경우"""
        assert needs_update("1.4.0", "1.4.0") is False
        assert needs_update("1.5.0", "1.4.0") is False
        assert needs_update("2.0.0", "1.9.9") is False


class TestIsForceUpdateRequiredFunction:
    """is_force_update_required 함수 테스트"""

    def test_force_update_required_true(self):
        """강제 업데이트가 필요한 경우 (current < minimum)"""
        assert is_force_update_required("1.2.0", "1.3.0") is True
        assert is_force_update_required("1.3.5", "2.0.0") is True
        assert is_force_update_required("1.3.5", "1.3.6") is True

    def test_force_update_required_false(self):
        """강제 업데이트가 불필요한 경우 (current >= minimum)"""
        assert is_force_update_required("1.3.0", "1.3.0") is False
        assert is_force_update_required("1.4.0", "1.3.0") is False
        assert is_force_update_required("2.0.0", "1.9.9") is False


class TestVersionRealWorldScenarios:
    """실제 사용 시나리오 테스트"""

    def test_scenario_force_update(self):
        """
        시나리오: 강제 업데이트
        - current: 1.2.0
        - minimum: 1.3.0
        - latest: 1.4.0
        → 강제 업데이트 필요
        """
        current = "1.2.0"
        minimum = "1.3.0"
        latest = "1.4.0"

        assert needs_update(current, latest) is True
        assert is_force_update_required(current, minimum) is True

    def test_scenario_recommended_update(self):
        """
        시나리오: 권장 업데이트
        - current: 1.3.0
        - minimum: 1.3.0
        - latest: 1.4.0
        → 권장 업데이트 (강제 아님)
        """
        current = "1.3.0"
        minimum = "1.3.0"
        latest = "1.4.0"

        assert needs_update(current, latest) is True
        assert is_force_update_required(current, minimum) is False

    def test_scenario_no_update(self):
        """
        시나리오: 업데이트 불필요
        - current: 1.4.0
        - minimum: 1.3.0
        - latest: 1.4.0
        → 업데이트 불필요
        """
        current = "1.4.0"
        minimum = "1.3.0"
        latest = "1.4.0"

        assert needs_update(current, latest) is False
        assert is_force_update_required(current, minimum) is False

    def test_scenario_ahead_of_latest(self):
        """
        시나리오: 최신 버전보다 높음 (개발 버전)
        - current: 1.5.0
        - minimum: 1.3.0
        - latest: 1.4.0
        → 업데이트 불필요
        """
        current = "1.5.0"
        minimum = "1.3.0"
        latest = "1.4.0"

        assert needs_update(current, latest) is False
        assert is_force_update_required(current, minimum) is False
