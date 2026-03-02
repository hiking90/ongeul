/// 키 이벤트의 문자열과 modifier 상태로부터 Hangul 엔진에 전달할 키 레이블을 추출한다.
///
/// 한글 모드에서 CapsLock의 영향을 무효화한다:
/// - CapsLock ON + Shift 없음 → 소문자로 변환 (CapsLock의 대문자화 취소)
/// - CapsLock ON + Shift → 대문자로 변환 (Shift 우선)
///
/// ASCII 문자/숫자/기호만 반환하며, 그 외에는 nil을 반환한다.
func keyLabel(characters: String, capsLock: Bool, shift: Bool) -> String? {
    guard !characters.isEmpty else { return nil }

    let ch = characters.first!

    // CapsLock 보정: 한글 모드에서 CapsLock 영향 무효화
    if ch.isASCII && ch.isLetter {
        if capsLock && !shift {
            return String(ch).lowercased()
        } else if capsLock && shift {
            return String(ch).uppercased()
        }
    }

    if ch.isASCII && (ch.isLetter || ch.isNumber || ch.isPunctuation || ch.isSymbol) {
        return String(ch)
    }

    return nil
}
