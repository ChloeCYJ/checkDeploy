# checkDeploy
checkDeploy
# Deploy Check

필요한 파일

- [check_deploy.sh]
- [check.conf]
- [MetaCountRunner.java]

실행

```bash
./check_deploy.sh
./check_deploy.sh KOR
./check_deploy.sh JPN
./check_deploy.sh CAM
```

- 인자를 안 주면 기본값은 `KOR`

체크 기준

- DB 체크는 코드 집계 테이블만 수행
- DB 결과는 2일전, 1일전, 당일 3일치 건수
- `NEWCODEINF`, `NEWCODEVAL`
  오늘 line/size 만 기록
- `CODEPROPERTIES`, `CODEINF`, `CODEVAL`
  오늘/전일 line, size, 변화율 기록
- 오늘 파일 없음
  `-` 로 기록
- 전일 파일 없음
  `-` 로 기록
- DB 조회 실패
  `FAIL`
- 그 외
  `SUCCESS`
- 오늘 파일 없음도 `FAIL` 로 바꾸고 싶으면 `check_deploy.sh` 안 주석 블록을 해제해서 사용

check.conf 에서 수정할 것

- `get_target_dir()`
- `get_output_file()`

결과 파일 형식

- 결과 파일은 1개만 생성
- 파일 안에는 2줄 저장
  1. `코드파일체크`
  2. `집계테이블체크`

파일 체크 라인 예시

```text
[20260428_코드파일체크] [[INF:-11%] [VALA:+13%] [PROPERTIES:34MB] [NEWCODEINF:450B] [NEWCODEVAL:330B]]
[20260428_코드파일체크] [[INF:당일X] [VALA:+13%] [PROPERTIES:34MB] [NEWCODEINF:당일X] [NEWCODEVAL:330B]]
```

DB 체크 라인 예시

```text
[20260428_집계테이블체크] [정상] [[당일 152건] [당일대비 전일 증감률 -15건] [당일대비 전전일 증감률 +12건] [CU : 2 / D : 1]]
```

정책

- `SUCCESS`, `FAIL` 둘 다 결과 파일 생성
- 상세도 둘 다 기록
- 500자 넘으면 각 줄은 뒤를 자르고 `...` 붙임
- 기존 임계치 비교 로직은 쉘 안에 주석으로 남겨둠

SMS 팀 탐지 방법

- 파일 SMS

```bash
grep '^코드파일체크|' /app/message/watch/kor/deploy_check_result.txt
```

- DB SMS

```bash
grep '^집계테이블체크|' /app/message/watch/kor/deploy_check_result.txt
```

종료 코드

- `0`: SUCCESS
- `2`: FAIL
