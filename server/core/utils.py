from datetime import datetime
from zoneinfo import ZoneInfo


KST = ZoneInfo("Asia/Seoul")

def _parse_kst(dt_str: str | None) -> datetime | None:
    if not dt_str:
        return None
    # 1) 문자열을 datetime으로
    dt = datetime.fromisoformat(dt_str)
    # 2) tz가 없으면 KST로 로컬라이즈, 있으면 그대로 사용
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=KST)
    return dt