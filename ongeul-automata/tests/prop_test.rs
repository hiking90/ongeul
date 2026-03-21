/// 프로퍼티 기반 테스트 (proptest)
///
/// 임의의 키 시퀀스에 대해 불변 조건을 검증한다:
/// 1. 어떤 키 시퀀스에도 패닉하지 않는다
/// 2. committed 출력은 항상 유효한 한글 음절 또는 자모이다
/// 3. 과도한 백스페이스에도 패닉하지 않는다
use proptest::prelude::*;

use ongeul_automata::{HangulEngine, InputMode};

const LAYOUT_2STD: &str = include_str!("../layouts/2-standard.json5");
const LAYOUT_3_390: &str = include_str!("../layouts/3-390.json5");
const LAYOUT_3_FINAL: &str = include_str!("../layouts/3-final.json5");

// ── 레이아웃별 자모 매핑 키셋 ──

/// 2벌식 표준: 자음 + 모음 + 쌍자음/쌍모음
const KEYS_2STD: &[&str] = &[
    // 소문자 (자음 + 모음)
    "r", "s", "e", "f", "a", "q", "t", "d", "w", "c", "z", "x", "v", "g", "k", "o", "i", "O", "j",
    "p", "u", "P", "h", "y", "n", "b", "m", "l", // 대문자 (쌍자음 + 쌍모음)
    "R", "E", "Q", "T", "W",
];

/// 3벌식 390: 초성 + 중성 + 종성 자모 키만 (숫자/문장부호 제외)
const KEYS_3_390: &[&str] = &[
    // 초성
    "k", "h", "u", "y", "i", ";", "n", "j", "l", "o", "0", "'", "p", "m", // 중성
    "f", "r", "6", "R", "t", "c", "e", "7", "v", "/", "4", "b", "9", "5", "g", "8", "d",
    // 종성
    "x", "F", "s", "S", "A", "w", "D", "C", "V", "z", "3", "X", "q", "2", "a", "!", "Z", "E", "W",
    "Q", "1",
];

/// 3벌식 최종: 초성 + 중성 + 종성 자모 키만 (숫자/문장부호 제외)
const KEYS_3_FINAL: &[&str] = &[
    // 초성
    "k", "h", "u", "y", "i", ";", "n", "j", "l", "o", "0", "'", "p", "m", // 중성
    "f", "r", "6", "G", "t", "c", "e", "7", "v", "/", "4", "b", "9", "5", "g", "8", "d",
    // 종성
    "x", "!", "V", "s", "E", "S", "A", "w", "@", "F", "D", "T", "%", "$", "R", "z", "3", "X", "q",
    "2", "a", "#", "Z", "C", "W", "Q", "1",
];

// ── 헬퍼 ──

fn key_strategy(keys: &'static [&'static str]) -> impl Strategy<Value = String> {
    prop::sample::select(keys).prop_map(|s| s.to_string())
}

fn create_engine(layout_json: &str) -> HangulEngine {
    let engine = HangulEngine::new();
    engine.load_layout(layout_json.to_string()).unwrap();
    engine.set_mode(InputMode::Korean);
    engine
}

/// committed 문자가 유효한 한글인지 검증
fn is_valid_hangul_char(c: char) -> bool {
    let cp = c as u32;
    (0xAC00..=0xD7A3).contains(&cp) // 완성형 한글 음절
        || (0x3131..=0x318E).contains(&cp) // 호환 자모
}

// ── 레이아웃별 테스트 매크로 ──

macro_rules! proptest_layout {
    ($name_no_panic:ident, $name_output:ident, $name_backspace:ident,
     $layout:expr, $keys:expr, $validator:expr) => {
        proptest! {
            #[test]
            fn $name_no_panic(keys in prop::collection::vec(key_strategy($keys), 0..100)) {
                let engine = create_engine($layout);
                for key in &keys {
                    let _ = engine.process_key(key.clone());
                }
                let _ = engine.flush();
                // 패닉 없이 완료되면 성공
            }

            #[test]
            fn $name_output(keys in prop::collection::vec(key_strategy($keys), 1..50)) {
                let engine = create_engine($layout);
                for key in &keys {
                    let result = engine.process_key(key.clone());
                    if let Some(committed) = &result.committed {
                        let validator: fn(char) -> bool = $validator;
                        prop_assert!(
                            committed.chars().all(validator),
                            "Invalid committed char in: {:?} (codepoints: {:?})",
                            committed,
                            committed.chars().map(|c| format!("U+{:04X}", c as u32)).collect::<Vec<_>>()
                        );
                    }
                }
            }

            #[test]
            fn $name_backspace(keys in prop::collection::vec(key_strategy($keys), 1..30)) {
                let engine = create_engine($layout);
                for key in &keys {
                    let _ = engine.process_key(key.clone());
                }
                // 입력한 것보다 더 많이 백스페이스 — 빈 상태에서도 패닉 없어야 함
                for _ in 0..keys.len() + 5 {
                    let _ = engine.backspace();
                }
            }
        }
    };
}

// ── 2벌식 표준 ──
proptest_layout!(
    no_panic_2std,
    output_is_valid_hangul_2std,
    backspace_never_panics_2std,
    LAYOUT_2STD,
    KEYS_2STD,
    is_valid_hangul_char
);

// ── 3벌식 390 ──
proptest_layout!(
    no_panic_3_390,
    output_is_valid_hangul_3_390,
    backspace_never_panics_3_390,
    LAYOUT_3_390,
    KEYS_3_390,
    is_valid_hangul_char
);

// ── 3벌식 최종 ──
proptest_layout!(
    no_panic_3_final,
    output_is_valid_hangul_3_final,
    backspace_never_panics_3_final,
    LAYOUT_3_FINAL,
    KEYS_3_FINAL,
    is_valid_hangul_char
);

// ── 레이아웃 간 교차 테스트 ──

proptest! {
    /// 레이아웃 로드 → 키 입력 → 다른 레이아웃 로드 → 패닉 없어야 함
    #[test]
    fn layout_switch_no_panic(
        keys1 in prop::collection::vec(key_strategy(KEYS_2STD), 1..20),
        keys2 in prop::collection::vec(key_strategy(KEYS_3_390), 1..20),
    ) {
        let engine = HangulEngine::new();
        engine.load_layout(LAYOUT_2STD.to_string()).unwrap();
        engine.set_mode(InputMode::Korean);
        for key in &keys1 {
            let _ = engine.process_key(key.clone());
        }
        // 레이아웃 전환 (flush 없이)
        engine.load_layout(LAYOUT_3_390.to_string()).unwrap();
        for key in &keys2 {
            let _ = engine.process_key(key.clone());
        }
        let _ = engine.flush();
    }

    /// 모드 토글 중 패닉 없어야 함
    #[test]
    fn mode_toggle_no_panic(keys in prop::collection::vec(key_strategy(KEYS_2STD), 1..50)) {
        let engine = create_engine(LAYOUT_2STD);
        for (i, key) in keys.iter().enumerate() {
            let _ = engine.process_key(key.clone());
            if i % 7 == 0 {
                let _ = engine.toggle_mode();
            }
        }
        let _ = engine.flush();
    }
}
