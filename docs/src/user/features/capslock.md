# CapsLock 정규화

Ongeul은 CapsLock 상태에 관계없이 일관된 입력을 제공합니다.

## 동작 방식

- **한글 모드**: CapsLock이 켜져 있어도 정상적으로 한글이 입력됩니다. CapsLock 상태를 무시합니다.
- **영문 모드**: CapsLock이 켜져 있으면 기존 대문자 동작이 그대로 유지됩니다.

## CapsLock + Shift

- 한글 모드에서 CapsLock + Shift 조합은 쌍자음 등 Shift 본래의 동작을 유지합니다.
- 영문 모드에서 CapsLock + Shift 조합은 소문자를 입력합니다 (macOS 기본 동작과 동일).

## 권장 설정

시스템 설정에서 **"Caps Lock으로 ABC 입력 소스 전환"** 옵션을 비활성화하세요. 이 옵션이 켜져 있으면 CapsLock을 누를 때 macOS가 입력 소스를 전환하려 시도하여 Ongeul과 충돌할 수 있습니다.
