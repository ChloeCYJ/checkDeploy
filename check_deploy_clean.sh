#!/bin/bash

set -u

CONF_PATH="/app/check/check.conf"
NAT_CD="${1:-KOR}"
TODAY=$(date '+%Y%m%d')
YESTERDAY=$(date -d '1 day ago' '+%Y%m%d')

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

mark_fail() {
  FAIL_REASON="$1"
  FAIL_LOG="${2:-$1}"
  RESULT="FAIL"
}

pct_diff() {
  local now_val=$1
  local old_val=$2
  local gap
  local abs_gap
  local sign

  if [[ "$old_val" -le 0 ]]; then
    echo "-"
    return
  fi

  gap=$((now_val - old_val))

  if [[ "$gap" -gt 0 ]]; then
    sign="+"
  elif [[ "$gap" -lt 0 ]]; then
    sign="-"
  else
    sign=""
  fi

  if [[ "$gap" -lt 0 ]]; then
    abs_gap=$(( -1 * gap ))
  else
    abs_gap=$gap
  fi

  echo "${sign}$(( abs_gap * 100 / old_val ))%"
}

# 집계테이블 어제/오늘 건수가 줄어드는지 확인
check_db_history() {
  local t_count=""

  if [[ "$DAILY_CHANGE_SUMMARY" =~ 당일건수[[:space:]](-?[0-9,]+)건 ]]; then
    t_count="${BASH_REMATCH[1]//,/}"
  fi

  if [[ -z "${t_count:-}" || ! "$t_count" =~ ^[0-9]+$ || "$t_count" -le 0 ]]; then
    mark_fail "당일집계건수없음" "today_count_missing ${TODAY}"
    return
  fi

  # 전일 데이터가 없으면 VV_LOG_CHANGE는 비어있을 수 있음(정상 케이스)
  if [[ -z "${VV_LOG_CHANGE:-}" ]]; then
    return
  fi

  if [[ "$VV_LOG_CHANGE" =~ ^-?[0-9]+$ && "$VV_LOG_CHANGE" -lt 0 ]]; then
    mark_fail "전일대비당일건수감소" "today_vs_yesterday_decrease ${TODAY}-${YESTERDAY} ${VV_LOG_CHANGE}"
  fi
}

[[ -f "$CONF_PATH" ]] || fail "Conf file not found: $CONF_PATH"
. "$CONF_PATH"

TARGET_DIR=$(get_target_dir "$NAT_CD")
OUTPUT_FILE=$(get_output_file "$NAT_CD")

[[ -d "$TARGET_DIR" ]] || fail "TARGET_DIR not found: $TARGET_DIR"
[[ -n "$OUTPUT_FILE" ]] || fail "OUTPUT_FILE is empty"

COMPARE_FILES=(
  "CODEINF"
  "CODEVAL"
)

NEW_FILES=(
  "CODEPROPERTIES"
  "NEWCODEINF"
  "NEWCODEVAL"
)

RESULT="SUCCESS"
FAIL_REASON=""
FAIL_LOG=""
FILE_LINE=""

DB_RAW_INFO=$(java -cp "/app/batch/lib/*:/app/check" MetaCountRunnerClean "$NAT_CD" \
  | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -n 1)
DB_INFO=""
REG_TYPE_SUMMARY=""
DAILY_CHANGE_SUMMARY=""
VV_LOG_CHANGE=""

if [[ -n "$DB_RAW_INFO" ]]; then
  DB_INFO=$(awk -F'@@' '{print $1}' <<< "$DB_RAW_INFO")
  REG_TYPE_SUMMARY=$(awk -F'@@' '{print $2}' <<< "$DB_RAW_INFO")
  DAILY_CHANGE_SUMMARY=$(awk -F'@@' '{print $3}' <<< "$DB_RAW_INFO")
  VV_LOG_CHANGE=$(awk -F'@@' '{print $4}' <<< "$DB_RAW_INFO")
fi

if [[ -z "$DB_RAW_INFO" ]]; then
  mark_fail "집계테이블건수없음" "db_summary_empty"
elif [[ "$DB_RAW_INFO" == "DB_ERROR" ]]; then
  mark_fail "DB조회실패" "db_query_failed"
elif [[ "$DB_INFO" != "OK" ]]; then
  mark_fail "DB결과포맷오류" "db_result_format_invalid"
else
  check_db_history
fi


# summary 조합 유효성 규칙
# 1) regTypeSummary 없고 daily(delta)Summary 있으면 정상
# 2) daily(delta)Summary 없고 regTypeSummary만 있으면 에러
# 3) 둘 다 없으면 에러
if [[ -n "$DB_RAW_INFO" && "$DB_RAW_INFO" != "DB_ERROR" && "$DB_INFO" == "OK" ]]; then
  if [[ -z "$REG_TYPE_SUMMARY" && -n "$DAILY_CHANGE_SUMMARY" ]]; then
    : # 정상
  elif [[ -n "$REG_TYPE_SUMMARY" && -z "$DAILY_CHANGE_SUMMARY" ]]; then
    mark_fail "집계테이블정보없음" "daily_summary_missing"
  elif [[ -z "$REG_TYPE_SUMMARY" && -z "$DAILY_CHANGE_SUMMARY" ]]; then
    mark_fail "코드유효값변경정보, 집계테이블정보 없음" "reg_type_and_daily_summary_missing"
  fi
fi

DB_DETAIL="$DAILY_CHANGE_SUMMARY"

if [[ -n "$REG_TYPE_SUMMARY" ]]; then
  if [[ -n "$DB_DETAIL" ]]; then
    DB_DETAIL="${DB_DETAIL} [${REG_TYPE_SUMMARY}]"
  else
    DB_DETAIL="[${REG_TYPE_SUMMARY}]"
  fi
fi


for name in "${COMPARE_FILES[@]}"; do
  label="${name#CODE}"
  file_now="${TARGET_DIR}/${name}.${TODAY}"
  file_old="${TARGET_DIR}/${name}.${YESTERDAY}"

  if [[ ! -f "$file_now" ]]; then
    FILE_LINE="${FILE_LINE}[${label}:당일X] "
    continue
  fi

  line_now=$(wc -l < "$file_now")
  if [[ -f "$file_old" ]]; then
    line_old=$(wc -l < "$file_old")
    line_pct=$(pct_diff "$line_now" "$line_old")
  else
    line_pct="-"
  fi

  FILE_LINE="${FILE_LINE}[${label}:${line_pct}] "
done

for name in "${NEW_FILES[@]}"; do
  label="${name#CODE}"
  file_now="${TARGET_DIR}/${name}.${TODAY}"

  if [[ ! -f "$file_now" ]]; then
    FILE_LINE="${FILE_LINE}[${label}:당일X] "
    continue
  fi

  size_now=$(wc -c < "$file_now")

  if [[ "$name" == "CODEPROPERTIES" ]]; then
    size_mb=$(awk -v bytes="$size_now" 'BEGIN { printf "%.0f", bytes / 1024 / 1024 }')
    FILE_LINE="${FILE_LINE}[${label}:${size_mb}MB] "
  else
    FILE_LINE="${FILE_LINE}[${label}:${size_now}B] "
  fi
done

FILE_LINE="[${TODAY}_코드파일체크] [${FILE_LINE% }]"

if [[ "$RESULT" == "SUCCESS" ]]; then
  if [[ -n "$DB_DETAIL" ]]; then
    DB_LINE="[${TODAY}_집계테이블체크] [정상] [${DB_DETAIL}]"
  else
    DB_LINE="[${TODAY}_집계테이블체크] [정상]"
  fi
elif [[ -n "$DB_RAW_INFO" ]]; then
  if [[ -n "$DB_DETAIL" ]]; then
    DB_LINE="[${TODAY}_집계테이블체크] [ERROR : ${FAIL_REASON}] [${DB_DETAIL}]"
  else
    DB_LINE="[${TODAY}_집계테이블체크] [ERROR : ${FAIL_REASON}]"
  fi
else
  DB_LINE="[${TODAY}_집계테이블체크] [ERROR : ${FAIL_REASON}]"
fi

if [[ ${#FILE_LINE} -gt 500 ]]; then
  FILE_LINE="${FILE_LINE:0:496}..."
fi

if [[ ${#DB_LINE} -gt 500 ]]; then
  DB_LINE="${DB_LINE:0:496}..."
fi

printf '%s\n%s\n' "$FILE_LINE" "$DB_LINE" > "$OUTPUT_FILE" || fail "Could not write output file: $OUTPUT_FILE"

if [[ "$RESULT" == "FAIL" ]]; then
  # 사용자 정의 실패 조건일 때 배치 로그에 메시지 출력 후 종료
  echo "FAIL: $FAIL_LOG" >&2
  exit 2
fi

exit 0
