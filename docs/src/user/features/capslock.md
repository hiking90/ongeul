# CapsLock

Ongeul은 CapsLock을 한/영 전환 키로 사용하거나, CapsLock 상태를 무시하는 정규화 기능을 제공합니다.

## CapsLock으로 한/영 전환

[설정](../preferences.md)에서 전환 키를 **CapsLock**으로 선택하면, CapsLock 키로 한/영을 전환할 수 있습니다.

### 동작 방식

- CapsLock을 누를 때마다 한글/영문 모드가 전환됩니다.
- CapsLock LED는 항상 꺼진 상태로 유지됩니다. 대문자 잠금 기능은 비활성화됩니다.
- [영문 잠금](english-lock.md) 상태에서는 CapsLock이 기존 대문자 잠금으로 동작합니다.

### 사전 설정

**시스템 설정 → 키보드**에서 다음을 확인하세요:

1. **CapsLock 지연 비활성화** — CapsLock 입력 지연을 끄세요. 지연이 활성화되어 있으면 CapsLock을 빠르게 누를 때 전환이 무시될 수 있습니다.
2. **"Caps Lock으로 ABC 입력 소스 전환"** 옵션 비활성화 — 이 옵션이 켜져 있으면 CapsLock을 누를 때 Ongeul에서 ABC로 전환되어 버립니다.

## CapsLock 정규화

CapsLock을 전환 키로 사용하지 않는 경우에도, Ongeul은 CapsLock 상태에 관계없이 일관된 입력을 제공합니다.

- **한글 모드**: CapsLock이 켜져 있어도 정상적으로 한글이 입력됩니다. CapsLock 상태를 무시합니다.
- **영문 모드**: CapsLock이 켜져 있으면 기존 대문자 동작이 그대로 유지됩니다.

### CapsLock + Shift

- 한글 모드에서 CapsLock + Shift 조합은 쌍자음 등 Shift 본래의 동작을 유지합니다.
- 영문 모드에서 CapsLock + Shift 조합은 소문자를 입력합니다 (macOS 기본 동작과 동일).

