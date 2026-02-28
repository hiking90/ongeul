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

> **손쉬운 사용 권한**이 부여된 경우 이 설정 없이도 정상 동작합니다. 권한에 대한 자세한 내용은 [한/영 전환 > 손쉬운 사용 권한](features/mode-switching.md#손쉬운-사용-권한-선택-사항)을 참고하세요.

## JetBrains IDE에서 Shift+Space 전환 시 공백이 입력됨

**원인**: JetBrains IDE(RustRover, IntelliJ, WebStorm 등)는 입력기가 Shift+Space를 처리했더라도 공백 문자를 삽입합니다. 이는 JetBrains 에디터의 텍스트 입력 레이어가 입력기 반환값과 무관하게 동작하기 때문입니다.

**해결**: Ongeul에 **손쉬운 사용(Accessibility)** 권한을 부여하세요.

1. Ongeul 설정에서 전환 키를 **Shift + Space** 로 선택합니다.
2. 권한 안내 다이얼로그가 표시되면 **권한 설정 열기** 를 클릭합니다.
3. **시스템 설정** → **개인 정보 보호 및 보안** → **손쉬운 사용** 에서 **Ongeul** 을 활성화합니다.

권한이 부여되면 다음 앱 전환 시 자동으로 적용되며, JetBrains IDE에서 공백 없이 한/영 전환이 동작합니다.

> 권한을 부여하지 않아도 대부분의 앱에서는 정상 동작합니다. JetBrains IDE에서 문제가 발생하는 경우에만 권한을 부여하세요.

## 디버그 로그 확인

문제를 진단하려면 콘솔에서 Ongeul의 로그를 확인할 수 있습니다.

```bash
log stream --predicate 'subsystem == "io.github.hiking90.inputmethod.Ongeul"'
```

