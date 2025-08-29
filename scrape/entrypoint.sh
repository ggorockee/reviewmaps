#!/bin/sh
set -e

# 환경변수로 키워드 리스트를 받음
KEYWORDS_STR=${SCRAPE_KEYWORDS}
# Kubernetes가 부여한 Pod의 순번 (0부터 시작), 없으면 0으로 기본값 설정
POD_INDEX=${JOB_COMPLETION_INDEX:-0}

# 자신의 인덱스에 맞는 키워드 선택 (cut 명령어는 1-based index를 사용하므로 +1)
keyword_index=$((POD_INDEX + 1))
SELECTED_KEYWORD=$(echo "$KEYWORDS_STR" | cut -d' ' -f$keyword_index)

# 디버깅을 위한 로그 출력
echo "Pod Index: $POD_INDEX"
echo "Keyword Index for cut: $keyword_index"
echo "Full Keyword String: '$KEYWORDS_STR'"
echo "Selected Keyword: '$SELECTED_KEYWORD'"

# 키워드가 정상적으로 선택되었는지 확인
if [ -z "$SELECTED_KEYWORD" ]; then
  echo "Error: 키워드를 선택하지 못했습니다. SCRAPE_KEYWORDS 환경변수와 Pod 인덱스를 확인하세요."
  exit 1
fi

# 선택된 키워드로 스크레이퍼 실행
exec python main.py mymilky --keyword "$SELECTED_KEYWORD"