import json
from pathlib import Path

from selenium_scraper.reviewnote_parse import image_url, list_objects, sanitize, to_record

FIXTURES = Path(__file__).parent / "fixtures"


def load_list() -> list[dict]:
    return list_objects(json.loads((FIXTURES / "list_page.json").read_text(encoding="utf-8")))


def test_list_objects_reads_objects():
    objs = load_list()
    assert [o["id"] for o in objs] == [1565099, 1564273]
    assert list_objects({"objects": None}) == []
    assert list_objects(None) == []


def test_image_url_uses_firebase_storage_with_encoded_key():
    url = image_url("campaigns/abc-123")
    assert url == (
        "https://firebasestorage.googleapis.com/v0/b/reviewnote-e92d9.appspot.com/o/"
        "campaigns%2Fabc-123?alt=media"
    )
    assert image_url(None) is None
    assert image_url("") is None


def test_record_without_detail_keeps_list_fields():
    obj = load_list()[0]
    rec = to_record(obj, None, "2026-11-27T00:00:00+00:00")
    assert rec["url"] == "https://www.reviewnote.co.kr/campaigns/1565099"
    assert rec["category"] == "여행"
    assert rec["campaignType"] == "방문형"
    assert rec["region"] == "강원 삼척시"
    assert rec["offer"].startswith("오션뷰 스파 객실")
    assert rec["possibleDays"] is None
    assert rec["detailFetched"] is False
    assert rec["raw"] is None


def test_record_with_detail_prefers_detail_and_drops_personal_info():
    obj = load_list()[0]
    detail = {
        "id": 1565099,
        "title": "푸른바다스파펜션 ",
        "possibleDays": " 일~목 ",
        "impossibleDays": "금, 토, 공휴일 전날",
        "possibleTime": "15:00 입실",
        "sameDayVisit": False,
        "scheduleInformation": "최소 3일 전 예약",
        "address1": "강원 삼척시 어딘가 1",
        "address2": " 101호",
        "keyword1": "삼척 펜션",
        "keyword2": "",
        "likes": [{"userId": 1}],
        "lat": 37.1,
        "lng": 129.1,
        "storeInformation": {"naverPlaceUrl": "https://naver.me/x"},
        "contact": "010-0000-0000",
        "user": {"name": "업체"},
        "userApply": {"id": 1},
    }
    rec = to_record(obj, detail, "2026-11-27T00:00:00+00:00")
    assert rec["title"] == "푸른바다스파펜션"
    assert rec["possibleDays"] == "일~목"
    assert rec["impossibleDays"] == "금, 토, 공휴일 전날"
    assert rec["sameDayVisit"] is False
    assert rec["naverPlaceUrl"] == "https://naver.me/x"
    assert rec["address"] == "강원 삼척시 어딘가 1 101호"
    assert rec["keywords"] == ["삼척 펜션"]
    assert rec["detailFetched"] is True
    for key in ("contact", "user", "userApply", "likes"):
        assert key not in rec["raw"]
    assert "possibleDays" in rec["raw"]


def test_list_values_are_joined_and_blank_becomes_none():
    obj = load_list()[1]
    rec = to_record(obj, {"possibleDays": ["월", "화", " "], "impossibleDays": "  "}, "t")
    assert rec["possibleDays"] == "월, 화"
    assert rec["impossibleDays"] is None


def test_sanitize_removes_only_sensitive_keys():
    assert sanitize({"contact": "x", "offer": "y"}) == {"offer": "y"}
