from __future__ import annotations
from typing import Iterable, Sequence, Any, Dict
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError
import psycopg2
import psycopg2.extras as pg_extras
import pandas as pd

from .config import Settings
from .logger import get_logger

log = get_logger("db")

def get_engine(settings: Settings) -> Engine:
    try:
        eng = create_engine(settings.db_url, pool_pre_ping=True, future=True)
        log.info("DB 엔진 생성 성공.")
        return eng
    except SQLAlchemyError as e:
        log.critical(f"DB 엔진 생성 실패: {e}")
        raise

def upsert_rows_psycopg2(
    engine: Engine,
    table: str,
    rows: pd.DataFrame,
    conflict_cols: Sequence[str],
    update_cols: Sequence[str],
) -> int:
    """빠른 벌크 UPSERT (Postgres). 변경된/삽입된 건수 추정 반환."""
    if rows.empty:
        log.info("UPSERT 대상 로우가 없습니다.")
        return 0

    # 1) SQL 파트들 조립 (f-string 중첩/백슬래시 방지)
    cols_in_order = list(rows.columns)
    cols_sql = ", ".join(f'"{c}"' for c in cols_in_order)
    conflict_sql = ", ".join(f'"{c}"' for c in conflict_cols)
    update_sql = ", ".join(f'"{c}" = EXCLUDED."{c}"' for c in update_cols)
    insert_sql = f'INSERT INTO "{table}" ({cols_sql}) VALUES %s'
    upsert_sql = f"{insert_sql} ON CONFLICT ({conflict_sql}) DO UPDATE SET {update_sql};"

    # 2) None/NaN 통일 + 키 컬럼 정리
    clean_df = rows.where(pd.notna(rows), None).copy()
    for c in conflict_cols:
        if c in clean_df.columns and clean_df[c].dtype == "object":
            clean_df[c] = clean_df[c].fillna("").astype(str).str.strip()

    values = [tuple(r) for r in clean_df.to_numpy()]

    # 3) raw_connection()은 context manager 아님 → 명시적 close/commit
    conn = engine.raw_connection()
    cur = None
    try:
        cur = conn.cursor()
        pg_extras.execute_values(cur, upsert_sql, values)
        conn.commit()
        # rowcount는 ON CONFLICT 시 정확치 않을 수 있음 → 안전하게 입력 건수 반환
        affected = len(values)
        log.info(f'UPSERT 완료: inserted/updated ≈ {affected} rows (table="{table}")')
        return affected
    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        log.error(f"UPSERT 중 오류: {e}")
        raise
    finally:
        if cur is not None:
            try:
                cur.close()
            except Exception:
                pass
        try:
            conn.close()
        except Exception:
            pass



def update_where_id(engine: Engine, table: str, row_id: int, data: Dict[str, Any]) -> bool:
    """단일 레코드 업데이트. 변경 사항 있으면 True."""
    to_set = {k: v for k, v in data.items() if v is not None}
    if not to_set:
        return False

    set_clause = ", ".join([f'"{k}" = :{k}' for k in to_set.keys()])
    q = text(f'UPDATE "{table}" SET {set_clause} WHERE id = :id')
    params = dict(to_set)
    params["id"] = row_id

    with engine.begin() as conn:
        res = conn.execute(q, params)
        updated = res.rowcount and res.rowcount > 0
        if updated:
            log.info(f'[{table}] id={row_id} 업데이트됨: keys={list(to_set.keys())}')
        return bool(updated)



