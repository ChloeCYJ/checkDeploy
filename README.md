# checkDeploy
checkDeploy
# Deploy Check

필요한 파일

- [check_deploy_clean.sh]
- [check.conf]
- [MetaCountRunnerClean.java]

실행

```bash
./check_deploy_clean.sh
./check_deploy_clean.sh KOR
./check_deploy_clean.sh JPN
./check_deploy_clean.sh CAM
```

- 인자를 안 주면 기본값은 `KOR`

체크 기준

- DB 체크는 코드 집계 테이블만 수행
- DB 결과는 당일건수 + (있을 때만) 전일/전전일 비교 증감건수와 `CU/D` 건수 중심으로 기록
- `CODEINF`, `CODEVAL`
  오늘/전일 line 변화율만 기록 (예: +13%, -11%)
- `CODEPROPERTIES`, `NEWCODEINF`, `NEWCODEVAL`
  오늘 size 만 기록 (`CODEPROPERTIES`는 MB, NEWCODE*는 B)
- 오늘 파일 없음
  `당일X` 로 기록
- 전일 파일 없음(비교 파일만 해당)
  전일 값/증감률을 `-` 로 기록
- DB 조회 실패
  `FAIL`
- 당일 집계건수 없으면 `FAIL`
- 전일대비 당일 증감건수가 음수면 `FAIL`
- 그 외
  `SUCCESS`

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
[20260505_집계테이블체크] [정상] [[당일건수 234,356건] [당일-전일 증감건수 26건] [당일-전전일 증감건수 -14건] [CU : 2 / D : 1]]
[20260505_집계테이블체크] [정상] [[당일건수 234,356건] [CU : 2 / D : 1]]
[20260505_집계테이블체크] [ERROR : 전일대비당일건수감소] [[당일건수 120건] [당일-전일 증감건수 -26건] [CU : 2 / D : 1]]
```

정책

- `SUCCESS`, `FAIL` 둘 다 결과 파일 생성
- 상세도 둘 다 기록
- 500자 넘으면 각 줄은 뒤를 자르고 `...` 붙임

SMS 팀 탐지 방법

- 파일 SMS

```bash
grep '코드파일체크' /app/message/watch/kor/deploy_check_result.txt
```

- DB SMS

```bash
grep '집계테이블체크' /app/message/watch/kor/deploy_check_result.txt
```

종료 코드

- `0`: SUCCESS
- `2`: FAIL
