#!/bin/sh
set -e


# 스크레이퍼 이름(필수). 없으면 에러
SCRAPER_NAME="${SCRAPER_NAME:-}"
if [ -z "$SCRAPER_NAME" ]; then
  echo "Error: SCRAPER_NAME 환경변수가 비어있습니다. ConfigMap에 SCRAPER_NAME을 설정하세요."
  exit 1
fi

# 키워드 목록 (병렬 모드에서 사용). 비어있으면 전체 실행로 간주
KEYWORDS_STR="${SCRAPE_KEYWORDS:-}"

# Kubernetes Indexed Job에서 주는 인덱스(0부터). 없으면 0
POD_INDEX="${JOB_COMPLETION_INDEX:-}"

echo "==== Entrypoint ===="
echo "SCRAPER_NAME: '$SCRAPER_NAME'"
echo "SCRAPE_KEYWORDS: '$KEYWORDS_STR'"
echo "JOB_COMPLETION_INDEX: '${POD_INDEX}'"

# 키워드가 비어있으면 --keyword 없이 전체 실행
if [ -z "$KEYWORDS_STR" ]; then
  echo "키워드가 비어있습니다. --keyword 없이 전체 실행을 진행합니다."
  exec python main.py "$SCRAPER_NAME"
fi

# 병렬 인덱스가 없으면(=비병렬) 첫 번째 키워드 사용
if [ -z "$POD_INDEX" ]; then
  echo "JOB_COMPLETION_INDEX가 없습니다(비병렬 모드로 판단). 첫 번째 키워드 사용."
  POD_INDEX=0
fi

# cut은 1-based 이므로 +1
keyword_index=$((POD_INDEX + 1))
SELECTED_KEYWORD="$(printf "%s" "$KEYWORDS_STR" | cut -d',' -f"$IDX" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

echo "Pod Index: $POD_INDEX"
echo "Keyword Index for cut (1-based): $keyword_index"
echo "Selected Keyword: '$SELECTED_KEYWORD'"

# 엣지: 인덱스 초과(키워드 없음)
if [ -z "$SELECTED_KEYWORD" ]; then
  echo "Error: 선택된 키워드가 없습니다. 인덱스가 키워드 개수보다 큽니다."
  exit 1
fi

# 실행
exec python main.py "$SCRAPER_NAME" --keyword "$SELECTED_KEYWORD"