/// HangulEngine 통합 테스트
/// 설계 문서의 핵심 테스트 시나리오를 검증한다.
use ongeul_automata::{HangulEngine, InputMode};

const LAYOUT_2BUL: &str = include_str!("../layouts/2-standard.json5");

fn create_engine() -> HangulEngine {
    let engine = HangulEngine::new();
    engine.load_layout(LAYOUT_2BUL.to_string()).unwrap();
    engine.set_mode(InputMode::Korean);
    engine
}

/// 키 시퀀스를 처리하고 (committed 누적, 최종 composing) 반환
fn process_keys(engine: &HangulEngine, keys: &[&str]) -> (String, Option<String>) {
    let mut committed = String::new();
    let mut composing = None;
    for key in keys {
        let result = engine.process_key(key.to_string());
        if let Some(c) = &result.committed {
            committed.push_str(c);
        }
        composing = result.composing;
    }
    (committed, composing)
}

// ── 핵심 시나리오 ──

#[test]
fn test_hangul_word() {
    // ㅎ ㅏ ㄴ ㄱ ㅡ ㄹ → "한글"
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["g", "k", "s", "r", "m", "f"]);
    assert_eq!(committed, "한");
    assert_eq!(composing, Some("글".to_string()));

    // flush로 최종 확정
    let result = engine.flush();
    assert_eq!(result.committed, Some("글".to_string()));
}

#[test]
fn test_double_jongseong_split() {
    // ㄱ ㅏ ㅂ ㅅ ㅣ → "갑" + "시"
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["r", "k", "q", "t", "l"]);
    assert_eq!(committed, "갑");
    assert_eq!(composing, Some("시".to_string()));
}

#[test]
fn test_double_vowel() {
    // ㄱ ㅗ ㅏ → "과"
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["r", "h", "k"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("과".to_string()));
}

#[test]
fn test_jongseong_split() {
    // ㄱ ㅏ ㄴ ㅕ → "가" + "녀"
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["r", "k", "s", "u"]);
    assert_eq!(committed, "가");
    assert_eq!(composing, Some("녀".to_string()));
}

// ── 백스페이스 테스트 ──

#[test]
fn test_backspace_jongseong() {
    // ㅎ ㅏ ㄴ + BS → "하"
    let engine = create_engine();
    process_keys(&engine, &["g", "k", "s"]);
    let result = engine.backspace();
    assert_eq!(result.composing, Some("하".to_string()));
}

#[test]
fn test_backspace_double_jongseong() {
    // ㄱ ㅏ ㅂ ㅅ + BS → "갑"
    let engine = create_engine();
    process_keys(&engine, &["r", "k", "q", "t"]);
    let result = engine.backspace();
    assert_eq!(result.composing, Some("갑".to_string()));
}

#[test]
fn test_backspace_double_vowel() {
    // ㄱ ㅗ ㅏ + BS → "고"
    let engine = create_engine();
    process_keys(&engine, &["r", "h", "k"]);
    let result = engine.backspace();
    assert_eq!(result.composing, Some("고".to_string()));
}

#[test]
fn test_backspace_to_empty() {
    // ㄱ + BS → 비어있음
    let engine = create_engine();
    process_keys(&engine, &["r"]);
    let result = engine.backspace();
    assert_eq!(result.composing, None);
    assert!(result.handled);

    // 빈 상태에서 BS → not handled
    let result = engine.backspace();
    assert!(!result.handled);
}

// ── 모드 전환 ──

#[test]
fn test_mode_toggle() {
    let engine = create_engine();
    assert_eq!(engine.get_mode(), InputMode::Korean);

    let result = engine.toggle_mode();
    assert!(result.handled);
    assert_eq!(engine.get_mode(), InputMode::English);

    // 영문 모드에서는 키를 그대로 committed로 반환 (단독 입력 소스 전략)
    let result = engine.process_key("r".to_string());
    assert!(result.handled);
    assert_eq!(result.committed, Some("r".to_string()));
    assert_eq!(result.composing, None);
}

#[test]
fn test_mode_toggle_flushes_composing() {
    // 한글 조합 중 toggle → 조합 텍스트가 committed로 반환
    let engine = create_engine();
    process_keys(&engine, &["g", "k"]); // "하" 조합 중

    let result = engine.toggle_mode();
    assert_eq!(result.committed, Some("하".to_string()));
    assert_eq!(result.composing, None);
    assert!(result.handled);
    assert_eq!(engine.get_mode(), InputMode::English);
}

#[test]
fn test_mode_switch_flushes() {
    // 한글 조합 중 영문 전환 → 조합 확정
    let engine = create_engine();
    process_keys(&engine, &["g", "k"]); // "하" 조합 중

    engine.set_mode(InputMode::English);
    // flush가 이미 set_mode 안에서 호출됨
    // 다시 한글 모드로 돌아와서 확인
    engine.set_mode(InputMode::Korean);
    let result = engine.backspace();
    assert!(!result.handled); // 비어있어야 함
}

// ── 복합 입력 시나리오 ──

#[test]
fn test_sentence_dangeul() {
    // "단글" = ㄷ ㅏ ㄴ ㄱ ㅡ ㄹ
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["e", "k", "s", "r", "m", "f"]);
    assert_eq!(committed, "단");
    assert_eq!(composing, Some("글".to_string()));
}

#[test]
fn test_double_jongseong_no_split() {
    // ㄱ ㅏ ㄹ ㄱ → "갈ㄱ"이 아닌 "갈" 상태에서 ㄱ+다음이 겹종성ㄺ
    // 실제: ㄱ(r) ㅏ(k) ㄹ(f) ㄱ(r) → "갈" 종성에 ㄹ, +ㄱ = ㄺ
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["r", "k", "f", "r"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("갉".to_string())); // 가 + ㄺ(겹종성)
    // 이어서 모음을 넣으면 겹종성 분리: ㄹ 유지, ㄱ 이동
    let result = engine.process_key("k".to_string()); // ㅏ
    assert_eq!(result.committed, Some("갈".to_string())); // ㄹ 유지
    assert_eq!(result.composing, Some("가".to_string())); // ㄱ+ㅏ
}

#[test]
fn test_ssangbieup_cannot_be_jongseong() {
    // ㄱ ㅏ + ㅃ → "가" 확정 + "ㅃ" (ㅃ는 종성 불가)
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["r", "k", "Q"]);
    assert_eq!(committed, "가");
    assert_eq!(composing, Some("ㅃ".to_string()));
}

#[test]
fn test_flush_and_continue() {
    let engine = create_engine();
    process_keys(&engine, &["g", "k", "s"]); // "한"
    let result = engine.flush();
    assert_eq!(result.committed, Some("한".to_string()));

    // flush 후 새 입력
    let (committed, composing) = process_keys(&engine, &["r", "m", "f"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("글".to_string()));
}

#[test]
fn test_vowel_only_input() {
    // ㅏ만 입력
    let engine = create_engine();
    let result = engine.process_key("k".to_string());
    assert_eq!(result.composing, Some("ㅏ".to_string()));
    assert!(result.handled);
}

// ── 모아주기 테스트 ──

#[test]
fn test_auto_reorder_vowel_then_consonant() {
    // 두벌식 모아주기: ㅏ → ㄱ → "가" (모음→자음 역전 교정)
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["k", "r"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("가".to_string()));
}

#[test]
fn test_auto_reorder_vowel_consonant_jongseong() {
    // 두벌식 모아주기: ㅏ → ㄱ → ㄴ → "간" (역전 교정 후 종성)
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["k", "r", "s"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("간".to_string()));
}

#[test]
fn test_eui_combination() {
    // ㅡ + ㅣ = ㅢ (겹모음)
    let engine = create_engine();
    let (committed, composing) = process_keys(&engine, &["d", "m", "l"]); // ㅇ ㅡ ㅣ
    assert_eq!(committed, "");
    assert_eq!(composing, Some("의".to_string()));
}
