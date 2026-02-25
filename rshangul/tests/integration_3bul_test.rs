/// 세벌식 HangulEngine 통합 테스트
/// 세벌식 390, 세벌식 최종 레이아웃의 핵심 시나리오를 검증한다.
use rshangul::{HangulEngine, InputMode};

const LAYOUT_390: &str = include_str!("../layouts/3-390.json5");
const LAYOUT_FINAL: &str = include_str!("../layouts/3-final.json5");

fn create_engine_390() -> HangulEngine {
    let engine = HangulEngine::new();
    engine.load_layout(LAYOUT_390.to_string()).unwrap();
    engine.set_mode(InputMode::Korean);
    engine
}

fn create_engine_final() -> HangulEngine {
    let engine = HangulEngine::new();
    engine.load_layout(LAYOUT_FINAL.to_string()).unwrap();
    engine.set_mode(InputMode::Korean);
    engine
}

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

// ── 세벌식 390 테스트 ──

#[test]
fn test_390_hangul_word() {
    // "한글" = ㅎ초(m) ㅏ중(f) ㄴ종(s) ㄱ초(k) ㅡ중(g) ㄹ종(w)
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["m", "f", "s", "k", "g", "w"]);
    assert_eq!(committed, "한");
    assert_eq!(composing, Some("글".to_string()));

    let result = engine.flush();
    assert_eq!(result.committed, Some("글".to_string()));
}

#[test]
fn test_390_double_vowel() {
    // ㄱ초(k) + ㅗ중(v) + ㅏ중(f) → "과" (겹모음 ㅘ)
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["k", "v", "f"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("과".to_string()));
}

#[test]
fn test_390_ssang_choseong() {
    // ㄱ초(k) + ㄱ초(k) + ㅏ중(f) → "까" (쌍자음 ㄲ)
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["k", "k", "f"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("까".to_string()));
}

#[test]
fn test_390_double_jongseong() {
    // ㄱ초(k) + ㅏ중(f) + ㄹ종(w) + ㄱ종(x) → "갉" (겹종성 ㄺ)
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["k", "f", "w", "x"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("갉".to_string()));
}

#[test]
fn test_390_no_jongseong_split() {
    // 세벌식은 종성 분리 없음 — 초성+중성 후 다른 초성이 오면 새 음절 시작
    // "나라" = ㄴ초(h) ㅏ중(f) ㄹ초(y) ㅏ중(f)
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["h", "f", "y", "f"]);
    assert_eq!(committed, "나");
    assert_eq!(composing, Some("라".to_string()));
}

#[test]
fn test_390_backspace_jongseong() {
    // ㅎ초(m) ㅏ중(f) ㄴ종(s) + BS → "하"
    let engine = create_engine_390();
    process_keys(&engine, &["m", "f", "s"]);
    let result = engine.backspace();
    assert_eq!(result.composing, Some("하".to_string()));
}

#[test]
fn test_390_backspace_ssang_choseong() {
    // ㄱ초(k) ㄱ초(k) + BS → "ㄱ" (쌍자음 해제)
    let engine = create_engine_390();
    process_keys(&engine, &["k", "k"]);
    let result = engine.backspace();
    assert_eq!(result.composing, Some("ㄱ".to_string()));
}

#[test]
fn test_390_backspace_double_vowel() {
    // ㄱ초(k) ㅗ중(v) ㅏ중(f) + BS → "고"
    let engine = create_engine_390();
    process_keys(&engine, &["k", "v", "f"]);
    let result = engine.backspace();
    assert_eq!(result.composing, Some("고".to_string()));
}

#[test]
fn test_390_ssang_jongseong() {
    // ㄱ초(k) ㅏ중(f) ㅅ종(q) ㅅ종(q) → "갔" (종성 쌍자음 ㅆ)
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["k", "f", "q", "q"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("갔".to_string()));
}

#[test]
fn test_390_shift_jongseong() {
    // 세벌식 390에서 Shift 종성: Q=ㅍ종, W=ㅌ종
    // ㄱ초(k) ㅏ중(f) ㅍ종(Q) → "갑"... 아닌, 종성 ㅍ = T idx 26
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["k", "f", "Q"]);
    assert_eq!(committed, "");
    // ㄱ+ㅏ+ㅍ종 = 갑 아닌 "갚" 확인
    // ㄱ(L=0)+ㅏ(V=0)+ㅍ(T=26) = 가+0*28+26 = AC00+26 = AC1A
    assert_eq!(composing, Some("갚".to_string()));
}

#[test]
fn test_390_direct_double_jongseong_key() {
    // 세벌식 390의 Shift 겹받침: D=ㄺ종(직접)
    // ㄱ초(k) ㅏ중(f) ㄺ종(D) → "갉"
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["k", "f", "D"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("갉".to_string()));
}

#[test]
fn test_390_eui() {
    // "의" = ㅇ초(j) ㅡ중(g) ㅣ중(d) → 겹모음 ㅢ
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["j", "g", "d"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("의".to_string()));
}

#[test]
fn test_390_mode_toggle() {
    let engine = create_engine_390();
    assert_eq!(engine.get_mode(), InputMode::Korean);
    let result = engine.toggle_mode();
    assert!(result.handled);
    assert_eq!(engine.get_mode(), InputMode::English);

    // 영문 모드: 키를 그대로 committed로 반환
    let result = engine.process_key("k".to_string());
    assert!(result.handled);
    assert_eq!(result.committed, Some("k".to_string()));
}

// ── 세벌식 390 Shift 매핑 테스트 ──

#[test]
fn test_390_shift_number_standalone() {
    // Shift 숫자: U→7, J→4, M→1
    let engine = create_engine_390();
    let (committed, composing) = process_keys(&engine, &["U"]);
    assert_eq!(committed, "7");
    assert_eq!(composing, None);

    let (committed, composing) = process_keys(&engine, &["J"]);
    assert_eq!(committed, "4");
    assert_eq!(composing, None);

    let (committed, composing) = process_keys(&engine, &["M"]);
    assert_eq!(committed, "1");
    assert_eq!(composing, None);
}

#[test]
fn test_390_shift_number_flush_composing() {
    // 조합 중 Shift 숫자 → 조합 확정 + 숫자 커밋
    let engine = create_engine_390();
    // ㄱ초(k) ㅏ중(f) → "가" 조합 중 → U(7) → "가7"
    let (committed, composing) = process_keys(&engine, &["k", "f", "U"]);
    assert_eq!(committed, "가7");
    assert_eq!(composing, None);
}

#[test]
fn test_390_shift_punctuation() {
    // Shift 문장부호: T→;, G→/, B→!
    let engine = create_engine_390();
    let (committed, _) = process_keys(&engine, &["T"]);
    assert_eq!(committed, ";");

    let (committed, _) = process_keys(&engine, &["G"]);
    assert_eq!(committed, "/");

    let (committed, _) = process_keys(&engine, &["B"]);
    assert_eq!(committed, "!");
}

#[test]
fn test_390_non_jamo_then_new_composing() {
    // 비자모 문자 후 새 조합 시작 검증
    let engine = create_engine_390();
    // U(7) → ㄱ초(k) ㅏ중(f) → 7 커밋 + "가" 조합
    let (committed, composing) = process_keys(&engine, &["U", "k", "f"]);
    assert_eq!(committed, "7");
    assert_eq!(composing, Some("가".to_string()));
}

// ── 세벌식 최종 테스트 ──

#[test]
fn test_final_hangul_word() {
    // "한글" — 최종과 390의 초성/중성/기본종성 키가 같음
    let engine = create_engine_final();
    let (committed, composing) = process_keys(&engine, &["m", "f", "s", "k", "g", "w"]);
    assert_eq!(committed, "한");
    assert_eq!(composing, Some("글".to_string()));
}

#[test]
fn test_final_yae_key_difference() {
    // 최종에서 ㅒ = G (Shift+g), 390에서는 R (Shift+r)
    let engine = create_engine_final();
    // ㅇ초(j) + ㅒ중(G)
    let (committed, composing) = process_keys(&engine, &["j", "G"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("얘".to_string()));
}

#[test]
fn test_final_direct_all_double_jongseong() {
    // 최종은 모든 겹받침을 직접 키로 지원
    let engine = create_engine_final();

    // ㄱ초(k) ㅏ중(f) ㄳ종(V) → "갃"
    let (committed, composing) = process_keys(&engine, &["k", "f", "V"]);
    assert_eq!(committed, "");
    // ㄱ(L=0)+ㅏ(V=0)+ㄳ(T=3) = AC00+3 = AC03
    assert_eq!(composing, Some("갃".to_string()));

    // flush 후 새 입력: ㄱ초(k) ㅏ중(f) ㄼ종(D) → T=11
    engine.flush();
    let (committed, composing) = process_keys(&engine, &["k", "f", "D"]);
    assert_eq!(committed, "");
    // ㄱ(L=0)+ㅏ(V=0)+ㄼ(T=11) = AC00+11 = AC0B
    assert_eq!(composing, Some("갋".to_string()));
}

#[test]
fn test_final_ssang_choseong() {
    // 최종도 쌍자음 조합 동일: ㄱ초(k)+ㄱ초(k)+ㅏ중(f) → "까"
    let engine = create_engine_final();
    let (committed, composing) = process_keys(&engine, &["k", "k", "f"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("까".to_string()));
}

#[test]
fn test_final_double_vowel() {
    // ㄱ초(k) ㅗ중(v) ㅏ중(f) → "과"
    let engine = create_engine_final();
    let (committed, composing) = process_keys(&engine, &["k", "v", "f"]);
    assert_eq!(committed, "");
    assert_eq!(composing, Some("과".to_string()));
}

#[test]
fn test_final_complex_sentence() {
    // "있다" = ㅇ초(j) ㅣ중(d) ㅆ종(2) ㄷ초(u) ㅏ중(f)
    let engine = create_engine_final();
    let (committed, composing) = process_keys(&engine, &["j", "d", "2", "u", "f"]);
    assert_eq!(committed, "있");
    assert_eq!(composing, Some("다".to_string()));
}

// ── 세벌식 최종 Shift 매핑 테스트 ──

#[test]
fn test_final_non_shift_remap() {
    // 비Shift 리매핑: ` → *, - → ), [ → (, ] → <, = → >, \ → :
    let engine = create_engine_final();
    let (committed, _) = process_keys(&engine, &["`"]);
    assert_eq!(committed, "*");

    let (committed, _) = process_keys(&engine, &["-"]);
    assert_eq!(committed, ")");

    let (committed, _) = process_keys(&engine, &["["]);
    assert_eq!(committed, "(");

    let (committed, _) = process_keys(&engine, &["]"]);
    assert_eq!(committed, "<");

    let (committed, _) = process_keys(&engine, &["="]);
    assert_eq!(committed, ">");

    let (committed, _) = process_keys(&engine, &["\\"]);
    assert_eq!(committed, ":");
}

#[test]
fn test_final_shift_number() {
    // Shift 숫자: Y→5, U→6, H→0, J→1, :→4
    let engine = create_engine_final();
    let (committed, _) = process_keys(&engine, &["Y"]);
    assert_eq!(committed, "5");

    let (committed, _) = process_keys(&engine, &["U"]);
    assert_eq!(committed, "6");

    let (committed, _) = process_keys(&engine, &["H"]);
    assert_eq!(committed, "0");

    let (committed, _) = process_keys(&engine, &["J"]);
    assert_eq!(committed, "1");

    let (committed, _) = process_keys(&engine, &[":"]);
    assert_eq!(committed, "4");
}

#[test]
fn test_final_shift_number_flush_composing() {
    // 조합 중 Shift 숫자 → 조합 확정 + 숫자 커밋
    let engine = create_engine_final();
    // ㄱ초(k) ㅏ중(f) → "가" 조합 중 → Y(5) → "가5"
    let (committed, composing) = process_keys(&engine, &["k", "f", "Y"]);
    assert_eq!(committed, "가5");
    assert_eq!(composing, None);
}

#[test]
fn test_final_shift_punctuation() {
    // Shift 문장부호: B→?, N→-, M→", ?→!
    let engine = create_engine_final();
    let (committed, _) = process_keys(&engine, &["B"]);
    assert_eq!(committed, "?");

    let (committed, _) = process_keys(&engine, &["N"]);
    assert_eq!(committed, "-");

    let (committed, _) = process_keys(&engine, &["M"]);
    assert_eq!(committed, "\"");

    let (committed, _) = process_keys(&engine, &["?"]);
    assert_eq!(committed, "!");
}

#[test]
fn test_final_special_unicode_symbols() {
    // 특수 유니코드: & → \u{201C} ("), * → \u{201D} ("), ~ → ※, " → ·
    let engine = create_engine_final();
    let (committed, _) = process_keys(&engine, &["&"]);
    assert_eq!(committed, "\u{201C}");  // 왼쪽 큰따옴표

    let (committed, _) = process_keys(&engine, &["*"]);
    assert_eq!(committed, "\u{201D}");  // 오른쪽 큰따옴표

    let (committed, _) = process_keys(&engine, &["~"]);
    assert_eq!(committed, "※");

    let (committed, _) = process_keys(&engine, &["\""]);
    assert_eq!(committed, "\u{00B7}");  // 가운뎃점 ·
}

#[test]
fn test_final_non_jamo_then_new_composing() {
    // 비자모 문자 후 새 조합 시작 검증
    let engine = create_engine_final();
    // Y(5) → ㄱ초(k) ㅏ중(f) → 5 커밋 + "가" 조합
    let (committed, composing) = process_keys(&engine, &["Y", "k", "f"]);
    assert_eq!(committed, "5");
    assert_eq!(composing, Some("가".to_string()));
}
