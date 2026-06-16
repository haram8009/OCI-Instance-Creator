# OCI Instance Creator

Docker Desktop에서 OCI Resource Manager Stack Apply를 반복 실행하고, 시작부터 성공, 실패, 중단까지 모든 주요 상태를 Discord webhook으로 알립니다.

## How to use

### 1. 준비물 확인

필수 준비물:

- Docker Desktop
- OCI Console에서 GUI로 만들어 둔 Resource Manager Stack
- Stack OCID
- Discord Webhook URL
- OCI API key pair

주의할 점:

- OCI API key는 인스턴스 SSH 접속 키와 다릅니다.
- `oci/config`의 `key_file=/root/.oci/...`는 네 노트북 루트 경로가 아니라 Docker 컨테이너 내부 경로입니다.
- 네 노트북에서는 이 프로젝트의 `./oci` 폴더에 파일을 넣으면 됩니다.

### 2. Discord Webhook 만들기

Discord에서 알림 받을 채널로 이동한 뒤:

```text
채널 설정
-> Integrations
-> Webhooks
-> New Webhook
-> Copy Webhook URL
```

복사한 URL은 나중에 `.env`의 `DISCORD_WEBHOOK_URL`에 넣습니다.

### 3. OCI API Key 만들기

OCI Console에서:

```text
우측 상단 Profile 아이콘
-> My profile
-> API keys
-> Add API key
-> Generate API key pair
```

private key 파일을 다운로드해서 프로젝트의 `oci/` 폴더에 둡니다.

예시:

```text
/Users/haram/dev/oci-instance-retry/oci/oci_api_key.pem
```

파일 이름은 꼭 `oci_api_key.pem`일 필요는 없습니다. 이름을 바꾸면 `oci/config`의 `key_file`도 같이 바꾸면 됩니다.

### 4. OCI config 만들기

예시 파일을 복사합니다.

```bash
cp oci/config.example oci/config
```

`oci/config`를 열고 OCI Console에서 나온 값을 넣습니다.

```ini
[DEFAULT]
user=ocid1.user.oc1..example
fingerprint=00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00
tenancy=ocid1.tenancy.oc1..example
region=ap-osaka-1
key_file=/root/.oci/oci_api_key.pem
```

각 값의 출처:

- `user`: OCI Console `My profile`의 사용자 OCID
- `fingerprint`: `My profile -> API keys`에 표시되는 fingerprint
- `tenancy`: Tenancy details의 Tenancy OCID
- `region`: Stack이 있는 리전, 예: Osaka는 `ap-osaka-1`
- `key_file`: 컨테이너 내부 기준 API private key 경로

Docker Compose가 아래처럼 현재 프로젝트의 `./oci`를 컨테이너의 `/root/.oci`로 연결합니다.

```yaml
volumes:
  - ./oci:/root/.oci:ro
```

그래서 실제 파일 위치와 config 경로는 이렇게 대응됩니다.

```text
내 노트북: ./oci/oci_api_key.pem
컨테이너: /root/.oci/oci_api_key.pem
```

권한을 맞춥니다.

```bash
chmod 700 oci
chmod 600 oci/config
chmod 600 oci/oci_api_key.pem
```

private key 파일명이 다르면 마지막 줄의 파일명도 바꿉니다.

### 5. 환경 변수 만들기

```bash
cp env.example .env
```

`.env`에서 최소한 아래 두 값은 실제 값으로 바꿉니다.

```env
OCI_STACK_ID=ocid1.ormstack.oc1.ap-osaka-1.xxxxxxxxxxxxxxxxx
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxxxxxxxx/yyyyyyyyy
```

`OCI_STACK_ID`는 OCI Console에서 확인합니다.

```text
OCI Console
-> Resource Manager
-> Stacks
-> 사용할 Stack
-> OCID
```

주요 옵션:

```env
OCI_CONFIG_PROFILE=DEFAULT
DISCORD_USERNAME=OCI A1 Retry
DISCORD_DELIVERY_REQUIRED=true
DISCORD_DELIVERY_ATTEMPTS=5
DISCORD_DELIVERY_RETRY_SECONDS=5
DISCORD_BOT_ENABLED=false
DISCORD_BOT_TOKEN=
DISCORD_GUILD_ID=
DISCORD_ALLOWED_USER_IDS=
DISCORD_ALLOWED_ROLE_IDS=
RETRY_INTERVAL_SECONDS=1800
MAX_WAIT_SECONDS=1800
MAX_ATTEMPTS=0
LOG_DIR=/app/logs
LOG_CLEANUP_ENABLED=true
LOG_RETENTION_RUNS=50
LOG_RETENTION_DAYS=14
CONTROL_DIR=/app/control
JOB_LOG_FETCH_ENABLED=true
JOB_LOG_TAIL_CHARS=900
OCI_CLI_EXTRA_ARGS=
```

`MAX_ATTEMPTS=0`은 무제한 재시도입니다. 테스트나 제한 실행이 필요하면 `MAX_ATTEMPTS=3`처럼 지정합니다.

Discord에서 중지/재시작 명령을 쓰려면 Discord Developer Portal에서 bot을 만들고 서버에 초대한 뒤 아래 값을 설정합니다.

```env
DISCORD_BOT_ENABLED=true
DISCORD_BOT_TOKEN=xxxxxxxxxxxxxxxx
DISCORD_GUILD_ID=123456789012345678
DISCORD_ALLOWED_USER_IDS=123456789012345678
DISCORD_ALLOWED_ROLE_IDS=
```

`DISCORD_GUILD_ID`를 넣으면 slash command가 해당 서버에 빠르게 등록됩니다. 권한은 `DISCORD_ALLOWED_USER_IDS`, `DISCORD_ALLOWED_ROLE_IDS`, 또는 Discord 서버 관리자 권한 중 하나로 통과합니다.

서버의 모든 사용자를 허용하려면 `@everyone` role ID를 `DISCORD_ALLOWED_ROLE_IDS`에 넣습니다. 보통 `@everyone` role ID는 서버 ID와 같습니다.

```env
DISCORD_GUILD_ID=123456789012345678
DISCORD_ALLOWED_USER_IDS=
DISCORD_ALLOWED_ROLE_IDS=123456789012345678
```

### 6. 실행 전 Stack 설정 확인

Apply는 실제 리소스를 생성하거나 변경합니다. 실행 전 OCI Console에서 Stack 설정을 확인하세요.

```text
Shape: VM.Standard.A1.Flex
OCPU: 4
Memory: 24GB
Boot Volume: 100GB
Public IPv4 address: Yes
Subnet: Public subnet
```

특히 `Public IPv4 address: Yes`가 아니면 인스턴스 생성 후 SSH 접속이 어려울 수 있습니다.

### 7. 실행

Docker Desktop을 켠 뒤 실행합니다.

```bash
docker compose up --build
```

백그라운드 실행:

```bash
docker compose up -d --build
```

로그 확인:

```bash
docker logs -f oci-instance-creator
tail -f logs/latest.log
```

중지:

```bash
docker compose down
```

성공하면 Discord로 성공 알림을 보내고 컨테이너가 종료됩니다.

Discord bot을 켠 경우 아래 slash command를 사용할 수 있습니다.

```text
/status
/pause
/resume
/stop
/restart
/shutdown
```

각 명령의 의미:

- `/status`: 현재 run 상태, attempt 번호, job ID, 다음 retry 예정, pending command를 확인합니다.
- `/pause`: 현재 실행 중인 attempt는 건드리지 않고, attempt가 끝난 뒤 다음 retry를 시작하지 않은 채 대기합니다.
- `/resume`: pause 상태에서 같은 run을 이어서 진행합니다.
- `/stop`: 현재 run을 종료합니다. Discord bot과 supervisor는 살아 있으므로 이후 `/restart`를 받을 수 있습니다.
- `/restart`: 현재 run을 종료한 뒤 새 `RUN_ID`로 처음부터 다시 시작합니다. 기존 run 로그는 삭제하지 않습니다.
- `/shutdown`: retry worker와 Discord control bot까지 종료합니다. 이 명령 뒤에는 Discord에서 `/restart`를 받을 수 없고, Docker로 컨테이너를 다시 올려야 합니다.

실사용 기준으로는 `/pause`는 “잠깐 보류”, `/stop`은 “이번 run은 여기서 종료”, `/restart`는 “새 기준으로 다시 시작”, `/shutdown`은 “Discord 제어까지 종료”입니다.

## 알림 동작

- 컨테이너 시작 시 Discord로 시작 알림을 보냅니다.
- 각 시도마다 `oci resource-manager job create-apply-job`를 실행합니다.
- Apply job이 `SUCCEEDED`면 성공 알림을 보내고 컨테이너를 종료합니다.
- Apply job이 `FAILED`, `CANCELED`, 또는 알 수 없는 상태면 실패 알림을 보내고 재시도합니다.
- OCI CLI 명령 자체가 실패해도 실패 알림을 보내고 재시도합니다.
- `MAX_ATTEMPTS`에 도달하면 최종 중단 알림을 보내고 종료합니다.
- `/pause`는 현재 attempt를 취소하지 않습니다. OCI apply job이 끝난 뒤 다음 retry 직전에 멈춥니다.
- `/stop`은 retry run만 종료하고 Discord 제어는 유지합니다.
- `/shutdown`은 Discord 제어까지 종료합니다.
- Discord 전송 실패는 기본적으로 조용히 넘기지 않습니다. 여러 번 재시도 후에도 실패하면 payload를 로그에 남기고 프로세스를 실패시킵니다.

## 로그 보존

`./logs`가 컨테이너의 `/app/logs`에 마운트됩니다.

```text
logs/
├── latest.log
└── runs/
    └── <RUN_ID>/
        ├── retry.log
        ├── attempts/
        │   └── attempt-1/
        │       ├── summary.json
        │       ├── oci-create-apply-job.out.json
        │       ├── oci-create-apply-job.err.log
        │       ├── oci-job.log
        │       └── oci-job.normalized.log
        └── discord/
            ├── *.json
            └── unsent/
```

Discord에 보낸 payload도 run별로 저장합니다. 전송 실패 payload는 `discord/unsent/` 아래에 보존합니다.

Discord 알림에는 전체 job log를 그대로 넣지 않고 핵심 오류 요약만 넣습니다. 전체 원문은 `oci-job.log`, 줄바꿈을 정리한 로그는 `oci-job.normalized.log`에 보존합니다.

로그 정리는 기본으로 켜져 있습니다.

```env
LOG_CLEANUP_ENABLED=true
LOG_RETENTION_RUNS=50
LOG_RETENTION_DAYS=14
DOCKER_LOG_MAX_SIZE=10m
DOCKER_LOG_MAX_FILE=3
```

`LOG_RETENTION_RUNS`는 현재 run 외에 보존할 과거 run 개수입니다. `LOG_RETENTION_DAYS`는 지정 일수보다 오래된 run 디렉터리를 삭제합니다. Docker stdout 로그는 `docker-compose.yml`의 `json-file` 로그 회전 설정으로 최대 크기와 파일 개수를 제한합니다.

## 검증

네트워크 없이 mock OCI와 mock Discord webhook으로 주요 알림 경로를 검증할 수 있습니다.

```bash
tests/smoke.sh
```

검증하는 경로:

- 성공 알림
- Resource Manager apply 실패 알림
- OCI CLI 명령 실패 알림
- 로그 파일 보존
- pause/resume 제어 상태
- stop/shutdown 제어 상태

## 구조

```text
.
├── Dockerfile
├── docker-compose.yml
├── env.example
├── retry.sh
├── scripts/
│   ├── bin/
│   │   ├── apply-once.sh
│   │   └── retry-loop.sh
│   └── lib/
│       ├── config.sh
│       ├── discord.sh
│       └── logging.sh
├── tests/
│   └── smoke.sh
├── logs/
└── oci/
```

역할:

- `retry.sh`: 컨테이너 entrypoint입니다.
- `scripts/bin/supervisor.sh`: Discord bot을 띄우고 retry loop의 stop/restart/shutdown exit code를 처리합니다.
- `scripts/bin/retry-loop.sh`: 재시도 횟수, 성공/실패 분기, Discord 알림 흐름을 담당합니다.
- `scripts/bin/apply-once.sh`: OCI Resource Manager apply job을 한 번 실행하고 결과 JSON을 남깁니다.
- `scripts/bin/discord-control-bot.py`: Discord slash command를 받아 control 파일에 pause/resume/stop/restart/shutdown 요청을 기록합니다.
- `scripts/lib/discord.sh`: Discord embed payload 생성, 전송 재시도, 미전송 payload 보존을 담당합니다.
- `scripts/lib/logging.sh`: 실행 로그와 run별 로그 디렉터리를 관리합니다.
- `scripts/lib/control.sh`: pause/resume/stop/restart/shutdown 명령과 status 파일을 관리합니다.
- `scripts/lib/config.sh`: 환경 변수 기본값과 검증을 담당합니다.

## 보안 주의

- `.env`에는 Discord Webhook URL과 bot token이 들어갈 수 있으므로 공개 저장소에 올리면 안 됩니다.
- `oci/config`와 API private key도 공개 저장소에 올리면 안 됩니다.
- 이 프로젝트의 `.gitignore`는 `.env`, `oci/config`, `oci/*.pem`, `logs/*`가 커밋되지 않도록 설정되어 있습니다.
- Apply는 실제 리소스를 생성하거나 변경합니다. Stack 안에 유료 리소스가 포함되어 있으면 실제 과금될 수 있습니다.
