#!/bin/bash

set -u

CONF_PATH="/app/check/check.conf"
NAT_CD="${1:-KOR}"
TODAY=$(date '+%Y%m%d')
YESTERDAY=$(date -d '1 day ago' '+%Y%m%d')
BEFORE_YESTERDAY=$(date -d '2 day ago' '+%Y%m%d')

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

format_number() {
  printf "%'d" "$1"
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

# 집계 결과를 당일/전일/전전일 형식으로 변환
format_db_info() {
  local rows
  local row
  local date_key
  local count_value
  local label
  local result=""

  IFS='|' read -r -a rows <<< "$1"

  for row in "${rows[@]}"; do
    if [[ "$row" =~ ^[[:space:]]*([0-9]{8})[[:space:]]+([0-9]+)[[:space:]]*건[[:space:]]*$ ]]; then
      date_key="${BASH_REMATCH[1]}"
      count_value="${BASH_REMATCH[2]}"

      if [[ "$date_key" == "$TODAY" ]]; then
        label="당일"
      elif [[ "$date_key" == "$YESTERDAY" ]]; then
        label="전일"
      elif [[ "$date_key" == "$BEFORE_YESTERDAY" ]]; then
        label="전전일"
      else
        label="$date_key"
      fi

      result="${result}[${label} $(format_number "$count_value")건] "
    fi
  done

  echo "${result% }"
}

# 집계테이블 어제/오늘 건수가 줄어드는지 확인
check_db_history() {
  local rows
  local y_count=""
  local t_count=""
  local curr_date
  local curr_count

  IFS='|' read -r -a rows <<< "$DB_INFO"

  for row in "${rows[@]}"; do
    if [[ "$row" =~ ^[[:space:]]*([0-9]{8})[[:space:]]+([0-9]+)[[:space:]]*건[[:space:]]*$ ]]; then
      curr_date="${BASH_REMATCH[1]}"
      curr_count="${BASH_REMATCH[2]}"

      if [[ "$curr_date" == "$YESTERDAY" ]]; then
        y_count="$curr_count"
      fi

      if [[ "$curr_date" == "$TODAY" ]]; then
        t_count="$curr_count"
      fi
    fi
  done

  # 정상 기준: 어제건수 <= 오늘건수
  if [[ -n "$y_count" && -n "$t_count" && "$t_count" -lt "$y_count" ]]; then
    FAIL_REASON="당일집계건수감소"
    FAIL_LOG="집계건수감소 ${YESTERDAY} ${y_count}건 > ${TODAY} ${t_count}건"
    RESULT="FAIL"
  fi
}

[[ -f "$CONF_PATH" ]] || fail "Conf file not found: $CONF_PATH"
. "$CONF_PATH"

TARGET_DIR=$(get_target_dir "$NAT_CD")
OUTPUT_FILE=$(get_output_file "$NAT_CD")

[[ -d "$TARGET_DIR" ]] || fail "TARGET_DIR not found: $TARGET_DIR"
[[ -n "$OUTPUT_FILE" ]] || fail "OUTPUT_FILE is empty"

COMPARE_FILES=(
  "CODEPROPERTIES"
  "CODEINF"
  "CODEVAL"
)

NEW_FILES=(
  "NEWCODEINF"
  "NEWCODEVAL"
)

RESULT="SUCCESS"
FAIL_REASON=""
FAIL_LOG=""
FILE_LINE="코드파일체크|${NAT_CD}|${TODAY}|기준:오늘/전일,없음:-"

DB_RAW_INFO=$(java -cp "/app/batch/lib/*:/app/check" MetaCountRunnerClean "$NAT_CD" \
  | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -n 1)
DB_INFO=""
REG_INFO=""

if [[ -n "$DB_RAW_INFO" ]]; then
  DB_INFO="${DB_RAW_INFO%%@@*}"

  if [[ "$DB_RAW_INFO" == *"@@"* ]]; then
    REG_INFO="${DB_RAW_INFO#*@@}"
  fi
fi

if [[ -z "$DB_INFO" ]]; then
  RESULT="FAIL"
  FAIL_REASON="집계테이블건수없음"
  FAIL_LOG="$FAIL_REASON"
elif [[ "$DB_INFO" == "DB_ERROR" ]]; then
  RESULT="FAIL"
  FAIL_REASON="DB조회실패"
  FAIL_LOG="$FAIL_REASON"
  DB_INFO=""
else
  check_db_history
  DB_INFO=$(format_db_info "$DB_INFO")
fi

if [[ -n "$REG_INFO" ]]; then
  if [[ -n "$DB_INFO" ]]; then
    DB_INFO="${DB_INFO} [${REG_INFO}]"
  else
    DB_INFO="[${REG_INFO}]"
  fi
fi

if [[ "$RESULT" == "SUCCESS" ]]; then
  DB_LINE="집계테이블체크|${NAT_CD}|${TODAY}|[정상] [${DB_INFO}]"
elif [[ -n "$DB_INFO" ]]; then
  DB_LINE="집계테이블체크|${NAT_CD}|${TODAY}|[ERROR : ${FAIL_REASON}] [${DB_INFO}]"
else
  DB_LINE="집계테이블체크|${NAT_CD}|${TODAY}|[ERROR : ${FAIL_REASON}]"
fi

for name in "${COMPARE_FILES[@]}"; do
  file_now="${TARGET_DIR}/${name}.${TODAY}"
  file_old="${TARGET_DIR}/${name}.${YESTERDAY}"

  if [[ ! -f "$file_now" ]]; then
    FILE_LINE="${FILE_LINE}|${name}:LINE -,사이즈 -"
    continue
  fi

  line_now=$(wc -l < "$file_now")
  size_now=$(wc -c < "$file_now")

  if [[ -f "$file_old" ]]; then
    line_old=$(wc -l < "$file_old")
    size_old=$(wc -c < "$file_old")
    line_pct=$(pct_diff "$line_now" "$line_old")
    size_pct=$(pct_diff "$size_now" "$size_old")
  else
    line_old="-"
    size_old="-"
    line_pct="-"
    size_pct="-"
  fi

  FILE_LINE="${FILE_LINE}|${name}:LINE ${line_now}/${line_old},사이즈 ${size_now}/${size_old},LINE ${line_pct},사이즈 ${size_pct}"
done

for name in "${NEW_FILES[@]}"; do
  file_now="${TARGET_DIR}/${name}.${TODAY}"

  if [[ ! -f "$file_now" ]]; then
    FILE_LINE="${FILE_LINE}|${name}:LINE -,사이즈 -"
    continue
  fi

  line_now=$(wc -l < "$file_now")
  size_now=$(wc -c < "$file_now")

  FILE_LINE="${FILE_LINE}|${name}:LINE ${line_now},사이즈 ${size_now}"
done

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
