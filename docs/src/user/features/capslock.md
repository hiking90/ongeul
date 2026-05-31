# CapsLock

Ongeul은 CapsLock을 한/영 전환 키로 사용하거나, CapsLock 상태를 무시하는 정규화 기능을 제공합니다.

## CapsLock으로 한/영 전환

[설정](../preferences.md)에서 전환 키를 **CapsLock**으로 선택하면, CapsLock 키로 한/영을 전환할 수 있습니다.

### 동작 방식

- CapsLock을 누를 때마다 한글/영문 모드가 전환됩니다.
- **CapsLock LED가 현재 입력 모드를 나타냅니다**: LED ON = 한글, LED OFF = 영문. 모드가 다른 경로(다른 전환 키 사용, 앱 전환에 따른 per-app 모드 복원 등)로 바뀌어도 LED가 자동으로 동기화됩니다.
- 본연의 대문자 잠금 기능은 비활성화됩니다 (CapsLock = 한/영 전환 키 용도). 대문자 잠금이 필요하면 다른 전환 키(우측 Command/Option 등)를 선택하세요.
- [영문 잠금](english-lock.md) 상태에서는 CapsLock이 기존 대문자 잠금으로 동작합니다.

### 사전 설정

1. **macOS CapsLock 지연 해제** — macOS는 CapsLock에 약 100–250ms 지연을 적용해 빠른 탭을 무시합니다. 이 지연을 끄지 않으면 짧은 탭으로 한/영 전환이 안 됩니다. macOS는 이 지연을 위한 시스템 설정 UI를 제공하지 *않으므로*, **터미널**에서 다음 명령으로 끕니다:

    ```bash
    hidutil property --set '{"CapsLockDelayOverride":0}'
    ```

    이 설정은 재부팅 시 초기화됩니다. 영구화하려면 LaunchAgent 등록이 필요합니다 (외부 참고: [CapsLockNoDelay](https://github.com/gkpln3/CapsLockNoDelay)).

2. **"Caps Lock 키로 ABC 입력 소스 전환" 옵션 비활성화** — **시스템 설정 → 키보드 → 입력 소스 → 편집...** 에서 *"Caps Lock 키로 ABC 입력 소스 전환"* 옵션을 끕니다. 켜져 있으면 CapsLock을 누를 때 macOS가 먼저 ABC로 전환해 Ongeul이 비활성화됩니다.

## CapsLock 정규화

CapsLock을 전환 키로 사용하지 않는 경우에도, Ongeul은 CapsLock 상태에 관계없이 일관된 입력을 제공합니다.

- **한글 모드**: CapsLock이 켜져 있어도 정상적으로 한글이 입력됩니다. CapsLock 상태를 무시합니다.
- **영문 모드**: CapsLock이 켜져 있으면 기존 대문자 동작이 그대로 유지됩니다.

### CapsLock + Shift

- 한글 모드에서 CapsLock + Shift 조합은 쌍자음 등 Shift 본래의 동작을 유지합니다.
- 영문 모드에서 CapsLock + Shift 조합은 소문자를 입력합니다 (macOS 기본 동작과 동일).

