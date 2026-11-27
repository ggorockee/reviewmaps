"""리뷰노트 목록·상세 응답을 저장용 레코드로 바꾸는 순수 함수 (브라우저 없이 테스트 가능)."""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

BASE_URL = "https://www.reviewnote.co.kr"
# 사이트가 실제로 쓰는 이미지 주소 (2026-11-27 확인, S3 주소는 404)
IMAGE_URL = (
    "https://firebasestorage.googleapis.com/v0/b/reviewnote-e92d9.appspot.com/o/{key}?alt=media"
)

SORT_TO_TYPE = {"VISIT": "방문형", "DELIVERY": "배송형", "PURCHASE": "구매형", "TAKEOUT": "포장형"}

# 개인정보·계정 정보는 저장하지 않는다 (업체 연락처, 신청자, 로그인 사용자 상태)
SENSITIVE_KEYS = frozenset(
    {
        "contact",
        "user",
        "userId",
        "applies",
        "userApply",
        "applyPersonalInfo",
        "isLiked",
        "likeCount",
        "isAdmin",
        "isAlreadyApplied",
        "hasActiveStoreApply",
        "hasCompletedStoreApply",
        "hasPreviousSelectedApply",
        "hasInsufficientBlogCampaigns",
    }
)


def image_url(image_key: str | None) -> str | None:
    if not image_key:
        return None
    return IMAGE_URL.format(key=quote(image_key, safe=""))


def campaign_url(campaign_id: int | str) -> str:
    return f"{BASE_URL}/campaigns/{campaign_id}"


def _text(value: Any) -> str | None:
    """문자열은 앞뒤 공백 제거, 목록은 쉼표로 합침, 빈 값은 None."""
    if value is None:
        return None
    if isinstance(value, (list, tuple)):
        joined = ", ".join(str(v).strip() for v in value if str(v).strip())
        return joined or None
    text = str(value).strip()
    return text or None


def _nested(obj: Any, *keys: str) -> Any:
    for key in keys:
        if not isinstance(obj, dict):
            return None
        obj = obj.get(key)
    return obj


def list_objects(body: Any) -> list[dict[str, Any]]:
    """목록 API(/api/v2/campaigns) 응답에서 캠페인 목록을 꺼낸다."""
    if isinstance(body, dict) and isinstance(body.get("objects"), list):
        return [o for o in body["objects"] if isinstance(o, dict) and "id" in o]
    return []


def sanitize(detail: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in detail.items() if k not in SENSITIVE_KEYS}


def to_record(
    list_obj: dict[str, Any], detail: dict[str, Any] | None, collected_at: str
) -> dict[str, Any]:
    """목록 항목과 상세 응답을 합쳐 레코드 하나를 만든다. 상세 값이 있으면 상세를 우선한다."""
    d = detail or {}

    def pick(key: str) -> Any:
        value = d.get(key)
        return value if value not in (None, "") else list_obj.get(key)

    sort = pick("sort")
    region = _text(" ".join(x for x in (pick("city"), _nested(list_obj, "sido", "name")) if x))
    return {
        "id": list_obj["id"],
        "url": campaign_url(list_obj["id"]),
        "title": _text(pick("title")),
        "status": pick("status"),
        "category": _nested(list_obj, "category", "title"),
        "campaignType": SORT_TO_TYPE.get(sort, sort),
        "channel": pick("channel"),
        "region": region,
        "offer": _text(pick("offer")),
        "information": _text(d.get("information")),
        "recruitCount": pick("infNum"),
        "applicantCount": pick("applicantCount"),
        "point": pick("infPoint"),
        "applyStartAt": d.get("applyStartAt"),
        "applyEndAt": pick("applyEndAt"),
        "reviewEndAt": pick("reviewEndAt"),
        "imageUrl": image_url(pick("imageKey")),
        # 상세에서만 나오는 값
        "address": _text(d.get("address")),
        "lat": d.get("lat"),
        "lng": d.get("lng"),
        "possibleDays": _text(d.get("possibleDays")),
        "impossibleDays": _text(d.get("impossibleDays")),
        "possibleTime": _text(d.get("possibleTime")),
        "sameDayVisit": d.get("sameDayVisit") if isinstance(d.get("sameDayVisit"), bool) else None,
        "scheduleInformation": _text(d.get("scheduleInformation")),
        "keyword": _text(d.get("keyword")),
        "naverPlaceUrl": _text(_nested(d, "storeInformation", "naverPlaceUrl")),
        "description": _text(d.get("description")),
        "detailFetched": detail is not None,
        "collectedAt": collected_at,
        "raw": sanitize(d) if detail is not None else None,
    }
