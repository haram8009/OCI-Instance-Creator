# OCI Instance Retry

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
RETRY_INTERVAL_SECONDS=1800
MAX_WAIT_SECONDS=1800
MAX_ATTEMPTS=0
LOG_DIR=/app/logs
JOB_LOG_FETCH_ENABLED=true
JOB_LOG_TAIL_CHARS=900
OCI_CLI_EXTRA_ARGS=
```

`MAX_ATTEMPTS=0`은 무제한 재시도입니다. 테스트나 제한 실행이 필요하면 `MAX_ATTEMPTS=3`처럼 지정합니다.

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
docker logs -f oci-a1-retry
tail -f logs/latest.log
```

중지:

```bash
docker compose down
```

성공하면 Discord로 성공 알림을 보내고 컨테이너가 종료됩니다.

## 알림 동작

- 컨테이너 시작 시 Discord로 시작 알림을 보냅니다.
- 각 시도마다 `oci resource-manager job create-apply-job`를 실행합니다.
- Apply job이 `SUCCEEDED`면 성공 알림을 보내고 컨테이너를 종료합니다.
- Apply job이 `FAILED`, `CANCELED`, 또는 알 수 없는 상태면 실패 알림을 보내고 재시도합니다.
- OCI CLI 명령 자체가 실패해도 실패 알림을 보내고 재시도합니다.
- `MAX_ATTEMPTS`에 도달하면 최종 중단 알림을 보내고 종료합니다.
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
        │       └── oci-job.log
        └── discord/
            ├── *.json
            └── unsent/
```

Discord에 보낸 payload도 run별로 저장합니다. 전송 실패 payload는 `discord/unsent/` 아래에 보존합니다.

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
- `scripts/bin/retry-loop.sh`: 재시도 횟수, 성공/실패 분기, Discord 알림 흐름을 담당합니다.
- `scripts/bin/apply-once.sh`: OCI Resource Manager apply job을 한 번 실행하고 결과 JSON을 남깁니다.
- `scripts/lib/discord.sh`: Discord embed payload 생성, 전송 재시도, 미전송 payload 보존을 담당합니다.
- `scripts/lib/logging.sh`: 실행 로그와 run별 로그 디렉터리를 관리합니다.
- `scripts/lib/config.sh`: 환경 변수 기본값과 검증을 담당합니다.

## 보안 주의

- `.env`에는 Discord Webhook URL이 들어가므로 공개 저장소에 올리면 안 됩니다.
- `oci/config`와 API private key도 공개 저장소에 올리면 안 됩니다.
- 이 프로젝트의 `.gitignore`는 `.env`, `oci/config`, `oci/*.pem`, `logs/*`가 커밋되지 않도록 설정되어 있습니다.
- Apply는 실제 리소스를 생성하거나 변경합니다. Stack 안에 유료 리소스가 포함되어 있으면 실제 과금될 수 있습니다.
