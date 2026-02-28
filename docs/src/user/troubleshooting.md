# 문제 해결

## 입력기 목록에 Ongeul이 보이지 않음

**원인**: macOS는 입력기 목록을 로그인 시점에 캐시합니다.

**해결**: 로그아웃 후 재로그인하세요. 설치 직후에는 반드시 이 과정이 필요합니다.

## Gatekeeper가 실행을 차단함

**원인**: 공증(notarization)되지 않은 빌드를 실행하려고 할 때 발생합니다.

**해결**:
1. **시스템 설정** → **개인 정보 보호 및 보안** 으로 이동합니다.
2. 하단에 "Ongeul.app이(가) 차단되었습니다" 메시지를 확인합니다.
3. **확인 없이 열기** 를 클릭합니다.

## 한글 조합이 되지 않음

다음 사항을 확인하세요:

1. 현재 입력 모드가 한글 모드인지 확인합니다 (오른쪽 Command로 전환).
2. 메뉴 막대의 아이콘이 한글 모드 아이콘으로 표시되는지 확인합니다.
3. 해당 앱에 [영문 잠금](features/english-lock.md)이 설정되어 있지 않은지 확인합니다.

## iTerm2에서 Shift+Space 전환 시 공백이 입력됨

**원인**: iTerm2는 Shift+Space 키 입력을 입력기에 전달하면서 동시에 공백 문자도 삽입합니다. 이로 인해 한/영 전환과 함께 불필요한 공백이 추가됩니다.

**해결**: iTerm2의 키 설정에서 Shift+Space를 **Bypass Terminal**로 지정하세요.

1. **iTerm2** → **Settings** (⌘,) → **Keys** → **Key Bindings** 탭을 엽니다.
2. **+** 버튼을 눌러 새 바인딩을 추가합니다.
3. **Keyboard Shortcut**에 Shift+Space를 입력합니다.
4. **Action**을 **Bypass Terminal**로 선택합니다.
5. **OK**를 눌러 저장합니다.

이렇게 설정하면 iTerm2가 Shift+Space를 가로채지 않고 입력기(Ongeul)에만 전달하므로, 공백 없이 한/영 전환이 정상 동작합니다.

## 디버그 로그 확인

문제를 진단하려면 콘솔에서 Ongeul의 로그를 확인할 수 있습니다.

```bash
log stream --predicate 'subsystem == "io.github.hiking90.inputmethod.Ongeul"'
```

