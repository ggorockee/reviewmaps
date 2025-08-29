#!/bin/sh
set -e

# 환경변수로 키워드 리스트를 받음 (공백으로 구분된 문자열)
# 예: "서울 대전 대구 부산"
KEYWORDS_STR=${SCRAPE_KEYWORDS}
# Kubernetes가 부여한 Pod의 순번 (0부터 시작)
POD_INDEX=${JOB_COMPLETION_INDEX:-0} # 기본값 0으로 로컬 테스트 지원

# 문자열을 배열로 변환 (sh 호환 방식)
set -f
KEYWORDS_ARRAY=($KEYWORDS_STR)
set +f

# 자신의 인덱스에 맞는 키워드 선택 (sh 배열 인덱스는 1부터 시작하도록 조정)
keyword_index=$((POD_INDEX + 1))
SELECTED_KEYWORD=$(echo "$KEYWORDS_STR" | cut -d' ' -f$keyword_index)

echo "Total Keywords: ${#KEYWORDS_ARRAY[@]}"
echo "Pod Index: $POD_INDEX"
echo "Selected Keyword: $SELECTED_KEYWORD"

# 선택된 키워드로 스크레이퍼 실행
exec python main.py mymilky --keyword "$SELECTED_KEYWORD"