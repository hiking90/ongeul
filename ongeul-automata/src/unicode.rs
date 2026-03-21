//! 한글 유니코드 상수 및 유틸리티
//!
//! - 음절 합성/분해 (SBase 공식)
//! - 호환 자모 ↔ 위치 자모 변환
//! - 자모 분류 (초/중/종성 판별)
//! - 겹종성/겹모음 분리 테이블

// ── 한글 유니코드 상수 ──

/// 한글 음절 시작 '가' (U+AC00)
pub const S_BASE: u32 = 0xAC00;
/// 초성 시작 'ᄀ' (U+1100)
pub const L_BASE: u32 = 0x1100;
/// 중성 시작 'ᅡ' (U+1161)
pub const V_BASE: u32 = 0x1161;
/// 종성 기준 (U+11A7) — 종성 없음 = 0
pub const T_BASE: u32 = 0x11A7;

pub const L_COUNT: u32 = 19;
pub const V_COUNT: u32 = 21;
pub const T_COUNT: u32 = 28;
pub const N_COUNT: u32 = V_COUNT * T_COUNT; // 588
pub const S_COUNT: u32 = L_COUNT * N_COUNT; // 11172

// ── 호환 자모 범위 (U+3131 ~ U+318E) ──

/// 호환 자모 자음 시작 'ㄱ' (U+3131)
pub const COMPAT_CONSONANT_START: u32 = 0x3131;
/// 호환 자모 자음 끝 'ㅎ' (U+3163 이전의 자음 범위)
pub const COMPAT_CONSONANT_END: u32 = 0x314E;
/// 호환 자모 모음 시작 'ㅏ' (U+314F)
pub const COMPAT_VOWEL_START: u32 = 0x314F;
/// 호환 자모 모음 끝 'ㅣ' (U+3163)
pub const COMPAT_VOWEL_END: u32 = 0x3163;

// ── 음절 합성/분해 ──

/// 초성(L), 중성(V), 종성(T) 인덱스로 한글 음절을 합성한다.
/// - `l`: 초성 인덱스 (0~18)
/// - `v`: 중성 인덱스 (0~20)
/// - `t`: 종성 인덱스 (0~27, 0이면 종성 없음)
pub fn compose_syllable(l: u32, v: u32, t: u32) -> Option<char> {
    if l >= L_COUNT || v >= V_COUNT || t >= T_COUNT {
        return None;
    }
    let code = S_BASE + l * N_COUNT + v * T_COUNT + t;
    char::from_u32(code)
}

/// 한글 음절을 초성(L), 중성(V), 종성(T) 인덱스로 분해한다.
/// 종성이 없으면 t = 0.
pub fn decompose_syllable(ch: char) -> Option<(u32, u32, u32)> {
    let code = ch as u32;
    if !(S_BASE..S_BASE + S_COUNT).contains(&code) {
        return None;
    }
    let offset = code - S_BASE;
    let l = offset / N_COUNT;
    let v = (offset % N_COUNT) / T_COUNT;
    let t = offset % T_COUNT;
    Some((l, v, t))
}

/// 초성/중성/종성 인덱스로 음절 문자열을 만든다.
/// 종성이 None이면 종성 없는 음절.
pub fn compose_syllable_char(l: u32, v: u32, t: Option<u32>) -> Option<char> {
    compose_syllable(l, v, t.unwrap_or(0))
}

// ── 호환 자모 ↔ 위치 자모 변환 ──

/// 호환 자모 자음 → 초성 인덱스 (L index)
/// ㄱ(0x3131)=0, ㄲ(0x3132)=1, ㄴ(0x3134)=2, ...
static COMPAT_TO_CHOSEONG: &[(u32, u32)] = &[
    (0x3131, 0),  // ㄱ
    (0x3132, 1),  // ㄲ
    (0x3134, 2),  // ㄴ
    (0x3137, 3),  // ㄷ
    (0x3138, 4),  // ㄸ
    (0x3139, 5),  // ㄹ
    (0x3141, 6),  // ㅁ
    (0x3142, 7),  // ㅂ
    (0x3143, 8),  // ㅃ
    (0x3145, 9),  // ㅅ
    (0x3146, 10), // ㅆ
    (0x3147, 11), // ㅇ
    (0x3148, 12), // ㅈ
    (0x3149, 13), // ㅉ
    (0x314A, 14), // ㅊ
    (0x314B, 15), // ㅋ
    (0x314C, 16), // ㅌ
    (0x314D, 17), // ㅍ
    (0x314E, 18), // ㅎ
];

/// 호환 자모 모음 → 중성 인덱스 (V index)
/// ㅏ(0x314F)=0, ㅐ(0x3150)=1, ...
static COMPAT_TO_JUNGSEONG: &[(u32, u32)] = &[
    (0x314F, 0),  // ㅏ
    (0x3150, 1),  // ㅐ
    (0x3151, 2),  // ㅑ
    (0x3152, 3),  // ㅒ
    (0x3153, 4),  // ㅓ
    (0x3154, 5),  // ㅔ
    (0x3155, 6),  // ㅕ
    (0x3156, 7),  // ㅖ
    (0x3157, 8),  // ㅗ
    (0x3158, 9),  // ㅘ
    (0x3159, 10), // ㅙ
    (0x315A, 11), // ㅚ
    (0x315B, 12), // ㅛ
    (0x315C, 13), // ㅜ
    (0x315D, 14), // ㅝ
    (0x315E, 15), // ㅞ
    (0x315F, 16), // ㅟ
    (0x3160, 17), // ㅠ
    (0x3161, 18), // ㅡ
    (0x3162, 19), // ㅢ
    (0x3163, 20), // ㅣ
];

/// 호환 자모 자음 → 종성 인덱스 (T index, 1~27)
/// 종성에는 ㄸ(0x3138), ㅃ(0x3143), ㅉ(0x3149)가 없다.
static COMPAT_TO_JONGSEONG: &[(u32, u32)] = &[
    (0x3131, 1),  // ㄱ
    (0x3132, 2),  // ㄲ
    (0x3133, 3),  // ㄳ
    (0x3134, 4),  // ㄴ
    (0x3135, 5),  // ㄵ
    (0x3136, 6),  // ㄶ
    (0x3137, 7),  // ㄷ
    (0x3139, 8),  // ㄹ
    (0x313A, 9),  // ㄺ
    (0x313B, 10), // ㄻ
    (0x313C, 11), // ㄼ
    (0x313D, 12), // ㄽ
    (0x313E, 13), // ㄾ
    (0x313F, 14), // ㄿ
    (0x3140, 15), // ㅀ
    (0x3141, 16), // ㅁ
    (0x3142, 17), // ㅂ
    (0x3144, 18), // ㅄ
    (0x3145, 19), // ㅅ
    (0x3146, 20), // ㅆ
    (0x3147, 21), // ㅇ
    (0x3148, 22), // ㅈ
    (0x314A, 23), // ㅊ
    (0x314B, 24), // ㅋ
    (0x314C, 25), // ㅌ
    (0x314D, 26), // ㅍ
    (0x314E, 27), // ㅎ
];

/// 종성 인덱스 → 호환 자모 코드포인트
static JONGSEONG_TO_COMPAT: &[u32] = &[
    0,      // 0: 종성 없음
    0x3131, // 1: ㄱ
    0x3132, // 2: ㄲ
    0x3133, // 3: ㄳ
    0x3134, // 4: ㄴ
    0x3135, // 5: ㄵ
    0x3136, // 6: ㄶ
    0x3137, // 7: ㄷ
    0x3139, // 8: ㄹ
    0x313A, // 9: ㄺ
    0x313B, // 10: ㄻ
    0x313C, // 11: ㄼ
    0x313D, // 12: ㄽ
    0x313E, // 13: ㄾ
    0x313F, // 14: ㄿ
    0x3140, // 15: ㅀ
    0x3141, // 16: ㅁ
    0x3142, // 17: ㅂ
    0x3144, // 18: ㅄ
    0x3145, // 19: ㅅ
    0x3146, // 20: ㅆ
    0x3147, // 21: ㅇ
    0x3148, // 22: ㅈ
    0x314A, // 23: ㅊ
    0x314B, // 24: ㅋ
    0x314C, // 25: ㅌ
    0x314D, // 26: ㅍ
    0x314E, // 27: ㅎ
];

/// 초성 인덱스 → 호환 자모 코드포인트
static CHOSEONG_TO_COMPAT: &[u32] = &[
    0x3131, // 0: ㄱ
    0x3132, // 1: ㄲ
    0x3134, // 2: ㄴ
    0x3137, // 3: ㄷ
    0x3138, // 4: ㄸ
    0x3139, // 5: ㄹ
    0x3141, // 6: ㅁ
    0x3142, // 7: ㅂ
    0x3143, // 8: ㅃ
    0x3145, // 9: ㅅ
    0x3146, // 10: ㅆ
    0x3147, // 11: ㅇ
    0x3148, // 12: ㅈ
    0x3149, // 13: ㅉ
    0x314A, // 14: ㅊ
    0x314B, // 15: ㅋ
    0x314C, // 16: ㅌ
    0x314D, // 17: ㅍ
    0x314E, // 18: ㅎ
];

/// 중성 인덱스 → 호환 자모 코드포인트
static JUNGSEONG_TO_COMPAT: &[u32] = &[
    0x314F, // 0: ㅏ
    0x3150, // 1: ㅐ
    0x3151, // 2: ㅑ
    0x3152, // 3: ㅒ
    0x3153, // 4: ㅓ
    0x3154, // 5: ㅔ
    0x3155, // 6: ㅕ
    0x3156, // 7: ㅖ
    0x3157, // 8: ㅗ
    0x3158, // 9: ㅘ
    0x3159, // 10: ㅙ
    0x315A, // 11: ㅚ
    0x315B, // 12: ㅛ
    0x315C, // 13: ㅜ
    0x315D, // 14: ㅝ
    0x315E, // 15: ㅞ
    0x315F, // 16: ㅟ
    0x3160, // 17: ㅠ
    0x3161, // 18: ㅡ
    0x3162, // 19: ㅢ
    0x3163, // 20: ㅣ
];

// ── 호환 자모 분류 ──

/// 호환 자모 자음인지 판별 (ㄱ~ㅎ, 겹자모 포함 0x3131~0x314E)
pub fn is_compat_consonant(ch: char) -> bool {
    let c = ch as u32;
    (COMPAT_CONSONANT_START..=COMPAT_CONSONANT_END).contains(&c)
}

/// 호환 자모 모음인지 판별 (ㅏ~ㅣ, 0x314F~0x3163)
pub fn is_compat_vowel(ch: char) -> bool {
    let c = ch as u32;
    (COMPAT_VOWEL_START..=COMPAT_VOWEL_END).contains(&c)
}

/// 호환 자모 자음을 초성 인덱스로 변환
pub fn compat_to_choseong(ch: char) -> Option<u32> {
    let c = ch as u32;
    COMPAT_TO_CHOSEONG
        .iter()
        .find(|(compat, _)| *compat == c)
        .map(|(_, idx)| *idx)
}

/// 호환 자모 모음을 중성 인덱스로 변환
pub fn compat_to_jungseong(ch: char) -> Option<u32> {
    let c = ch as u32;
    COMPAT_TO_JUNGSEONG
        .iter()
        .find(|(compat, _)| *compat == c)
        .map(|(_, idx)| *idx)
}

/// 호환 자모 자음을 종성 인덱스로 변환
/// 종성 불가 자음(ㄸ, ㅃ, ㅉ)은 None 반환
pub fn compat_to_jongseong(ch: char) -> Option<u32> {
    let c = ch as u32;
    COMPAT_TO_JONGSEONG
        .iter()
        .find(|(compat, _)| *compat == c)
        .map(|(_, idx)| *idx)
}

/// 초성 인덱스를 호환 자모로 변환
pub fn choseong_to_compat(l: u32) -> Option<char> {
    CHOSEONG_TO_COMPAT
        .get(l as usize)
        .and_then(|&c| char::from_u32(c))
}

/// 중성 인덱스를 호환 자모로 변환
pub fn jungseong_to_compat(v: u32) -> Option<char> {
    JUNGSEONG_TO_COMPAT
        .get(v as usize)
        .and_then(|&c| char::from_u32(c))
}

/// 종성 인덱스를 호환 자모로 변환 (0이면 None)
pub fn jongseong_to_compat(t: u32) -> Option<char> {
    if t == 0 {
        return None;
    }
    JONGSEONG_TO_COMPAT
        .get(t as usize)
        .and_then(|&c| char::from_u32(c))
}

/// 종성 인덱스에 대응하는 초성 인덱스 반환.
/// 종성 분리 시 다음 음절의 초성으로 이동할 때 사용.
pub fn jongseong_to_choseong(t: u32) -> Option<u32> {
    let compat = jongseong_to_compat(t)?;
    compat_to_choseong(compat)
}

/// 초성 인덱스에 대응하는 종성 인덱스 반환.
pub fn choseong_to_jongseong(l: u32) -> Option<u32> {
    let compat = choseong_to_compat(l)?;
    compat_to_jongseong(compat)
}

// ── 종성 불가 자음 ──

/// 종성으로 올 수 없는 호환 자모 자음: ㄸ(0x3138), ㅃ(0x3143), ㅉ(0x3149)
pub fn is_jongseong_impossible(ch: char) -> bool {
    matches!(ch as u32, 0x3138 | 0x3143 | 0x3149)
}

// ── 겹종성 분리 테이블 ──

/// 겹종성을 (첫째 종성 인덱스, 둘째 호환 자모)로 분리.
/// 둘째 자모는 다음 음절의 초성이 된다.
/// 겹종성 종성 인덱스 → (첫째 종성 인덱스, 둘째 호환 자모)
static DOUBLE_JONGSEONG_SPLIT: &[(u32, (u32, u32))] = &[
    (3, (1, 0x3145)),   // ㄳ(3) → ㄱ(1) + ㅅ
    (5, (4, 0x3148)),   // ㄵ(5) → ㄴ(4) + ㅈ
    (6, (4, 0x314E)),   // ㄶ(6) → ㄴ(4) + ㅎ
    (9, (8, 0x3131)),   // ㄺ(9) → ㄹ(8) + ㄱ
    (10, (8, 0x3141)),  // ㄻ(10) → ㄹ(8) + ㅁ
    (11, (8, 0x3142)),  // ㄼ(11) → ㄹ(8) + ㅂ
    (12, (8, 0x3145)),  // ㄽ(12) → ㄹ(8) + ㅅ
    (13, (8, 0x314C)),  // ㄾ(13) → ㄹ(8) + ㅌ
    (14, (8, 0x314D)),  // ㄿ(14) → ㄹ(8) + ㅍ
    (15, (8, 0x314E)),  // ㅀ(15) → ㄹ(8) + ㅎ
    (18, (17, 0x3145)), // ㅄ(18) → ㅂ(17) + ㅅ
];

/// 겹종성 분리: 종성 인덱스 → Some((첫째 종성 인덱스, 둘째 호환 자모))
pub fn split_double_jongseong(t: u32) -> Option<(u32, char)> {
    DOUBLE_JONGSEONG_SPLIT
        .iter()
        .find(|(idx, _)| *idx == t)
        .and_then(|(_, (first, second))| char::from_u32(*second).map(|ch| (*first, ch)))
}

/// 겹종성인지 판별
pub fn is_double_jongseong(t: u32) -> bool {
    DOUBLE_JONGSEONG_SPLIT.iter().any(|(idx, _)| *idx == t)
}

// ── 겹모음 분리 테이블 ──

/// 겹모음을 (첫째 중성 인덱스, 둘째 중성 인덱스)로 분리.
static DOUBLE_JUNGSEONG_SPLIT: &[(u32, (u32, u32))] = &[
    (9, (8, 0)),    // ㅘ(9) → ㅗ(8) + ㅏ(0)
    (10, (8, 1)),   // ㅙ(10) → ㅗ(8) + ㅐ(1)
    (11, (8, 20)),  // ㅚ(11) → ㅗ(8) + ㅣ(20)
    (14, (13, 4)),  // ㅝ(14) → ㅜ(13) + ㅓ(4)
    (15, (13, 5)),  // ㅞ(15) → ㅜ(13) + ㅔ(5)
    (16, (13, 20)), // ㅟ(16) → ㅜ(13) + ㅣ(20)
    (19, (18, 20)), // ㅢ(19) → ㅡ(18) + ㅣ(20)
];

/// 겹모음 분리: 중성 인덱스 → Some((첫째 중성 인덱스, 둘째 중성 인덱스))
pub fn split_double_jungseong(v: u32) -> Option<(u32, u32)> {
    DOUBLE_JUNGSEONG_SPLIT
        .iter()
        .find(|(idx, _)| *idx == v)
        .map(|(_, pair)| *pair)
}

/// 겹모음인지 판별
pub fn is_double_jungseong(v: u32) -> bool {
    DOUBLE_JUNGSEONG_SPLIT.iter().any(|(idx, _)| *idx == v)
}

// ── 위치 자모 (세벌식용) ──

/// 위치 초성인지 (U+1100~U+1112)
pub fn is_choseong(ch: char) -> bool {
    let c = ch as u32;
    (L_BASE..L_BASE + L_COUNT).contains(&c)
}

/// 위치 중성인지 (U+1161~U+1175)
pub fn is_jungseong(ch: char) -> bool {
    let c = ch as u32;
    (V_BASE..V_BASE + V_COUNT).contains(&c)
}

/// 위치 종성인지 (U+11A8~U+11C2)
pub fn is_jongseong(ch: char) -> bool {
    let c = ch as u32;
    (T_BASE + 1..T_BASE + T_COUNT).contains(&c)
}

/// 한글 자모인지 판별 (위치 자모 초/중/종성 + 호환 자모 자음/모음)
pub fn is_korean_jamo(ch: char) -> bool {
    is_choseong(ch)
        || is_jungseong(ch)
        || is_jongseong(ch)
        || is_compat_consonant(ch)
        || is_compat_vowel(ch)
}

/// 위치 초성 → 초성 인덱스
pub fn choseong_to_index(ch: char) -> Option<u32> {
    if is_choseong(ch) {
        Some(ch as u32 - L_BASE)
    } else {
        None
    }
}

/// 위치 중성 → 중성 인덱스
pub fn jungseong_to_index(ch: char) -> Option<u32> {
    if is_jungseong(ch) {
        Some(ch as u32 - V_BASE)
    } else {
        None
    }
}

/// 위치 종성 → 종성 인덱스
pub fn jongseong_to_index(ch: char) -> Option<u32> {
    if is_jongseong(ch) {
        Some(ch as u32 - T_BASE)
    } else {
        None
    }
}

// ── 한글 음절 판별 ──

/// 한글 완성형 음절인지 (가~힣)
pub fn is_syllable(ch: char) -> bool {
    let c = ch as u32;
    (S_BASE..S_BASE + S_COUNT).contains(&c)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compose_syllable() {
        // 가 = L(0) + V(0) + T(0)
        assert_eq!(compose_syllable(0, 0, 0), Some('가'));
        // 힣 = L(18) + V(20) + T(27)
        assert_eq!(compose_syllable(18, 20, 27), Some('힣'));
        // 한 = ㅎ(18) + ㅏ(0) + ㄴ(4)
        assert_eq!(compose_syllable(18, 0, 4), Some('한'));
        // 글 = ㄱ(0) + ㅡ(18) + ㄹ(8)
        assert_eq!(compose_syllable(0, 18, 8), Some('글'));
        // 범위 초과
        assert_eq!(compose_syllable(19, 0, 0), None);
    }

    #[test]
    fn test_decompose_syllable() {
        assert_eq!(decompose_syllable('가'), Some((0, 0, 0)));
        assert_eq!(decompose_syllable('힣'), Some((18, 20, 27)));
        assert_eq!(decompose_syllable('한'), Some((18, 0, 4)));
        assert_eq!(decompose_syllable('글'), Some((0, 18, 8)));
        // 비한글
        assert_eq!(decompose_syllable('A'), None);
    }

    #[test]
    fn test_roundtrip() {
        // 합성 → 분해 → 재합성 라운드트립
        for l in 0..L_COUNT {
            for v in 0..V_COUNT {
                for t in 0..T_COUNT {
                    let ch = compose_syllable(l, v, t).unwrap();
                    let (dl, dv, dt) = decompose_syllable(ch).unwrap();
                    assert_eq!((l, v, t), (dl, dv, dt));
                }
            }
        }
    }

    #[test]
    fn test_compat_consonant_classification() {
        assert!(is_compat_consonant('ㄱ'));
        assert!(is_compat_consonant('ㅎ'));
        assert!(is_compat_consonant('ㄲ'));
        assert!(!is_compat_consonant('ㅏ'));
        assert!(!is_compat_consonant('A'));
    }

    #[test]
    fn test_compat_vowel_classification() {
        assert!(is_compat_vowel('ㅏ'));
        assert!(is_compat_vowel('ㅣ'));
        assert!(!is_compat_vowel('ㄱ'));
        assert!(!is_compat_vowel('A'));
    }

    #[test]
    fn test_compat_to_choseong() {
        assert_eq!(compat_to_choseong('ㄱ'), Some(0));
        assert_eq!(compat_to_choseong('ㅎ'), Some(18));
        assert_eq!(compat_to_choseong('ㄲ'), Some(1));
        assert_eq!(compat_to_choseong('ㅏ'), None);
    }

    #[test]
    fn test_compat_to_jungseong() {
        assert_eq!(compat_to_jungseong('ㅏ'), Some(0));
        assert_eq!(compat_to_jungseong('ㅣ'), Some(20));
        assert_eq!(compat_to_jungseong('ㄱ'), None);
    }

    #[test]
    fn test_compat_to_jongseong() {
        assert_eq!(compat_to_jongseong('ㄱ'), Some(1));
        assert_eq!(compat_to_jongseong('ㅎ'), Some(27));
        // 종성 불가
        assert_eq!(compat_to_jongseong('ㄸ'), None);
        assert_eq!(compat_to_jongseong('ㅃ'), None);
        assert_eq!(compat_to_jongseong('ㅉ'), None);
    }

    #[test]
    fn test_index_to_compat_roundtrip() {
        // 초성 라운드트립
        for (compat, idx) in COMPAT_TO_CHOSEONG {
            let ch = char::from_u32(*compat).unwrap();
            assert_eq!(compat_to_choseong(ch), Some(*idx));
            assert_eq!(choseong_to_compat(*idx), Some(ch));
        }
        // 중성 라운드트립
        for (compat, idx) in COMPAT_TO_JUNGSEONG {
            let ch = char::from_u32(*compat).unwrap();
            assert_eq!(compat_to_jungseong(ch), Some(*idx));
            assert_eq!(jungseong_to_compat(*idx), Some(ch));
        }
    }

    #[test]
    fn test_jongseong_impossible() {
        assert!(is_jongseong_impossible('ㄸ'));
        assert!(is_jongseong_impossible('ㅃ'));
        assert!(is_jongseong_impossible('ㅉ'));
        assert!(!is_jongseong_impossible('ㄱ'));
        assert!(!is_jongseong_impossible('ㅎ'));
    }

    #[test]
    fn test_split_double_jongseong() {
        // ㄳ(3) → ㄱ(1) + ㅅ
        assert_eq!(split_double_jongseong(3), Some((1, 'ㅅ')));
        // ㄵ(5) → ㄴ(4) + ㅈ
        assert_eq!(split_double_jongseong(5), Some((4, 'ㅈ')));
        // ㅄ(18) → ㅂ(17) + ㅅ
        assert_eq!(split_double_jongseong(18), Some((17, 'ㅅ')));
        // 단일 종성
        assert_eq!(split_double_jongseong(1), None);
    }

    #[test]
    fn test_split_double_jungseong() {
        // ㅘ(9) → ㅗ(8) + ㅏ(0)
        assert_eq!(split_double_jungseong(9), Some((8, 0)));
        // ㅢ(19) → ㅡ(18) + ㅣ(20)
        assert_eq!(split_double_jungseong(19), Some((18, 20)));
        // 단일 모음
        assert_eq!(split_double_jungseong(0), None);
    }

    #[test]
    fn test_jongseong_choseong_conversion() {
        // ㄱ 종성(1) → ㄱ 초성(0)
        assert_eq!(jongseong_to_choseong(1), Some(0));
        // ㄴ 종성(4) → ㄴ 초성(2)
        assert_eq!(jongseong_to_choseong(4), Some(2));
        // ㅎ 종성(27) → ㅎ 초성(18)
        assert_eq!(jongseong_to_choseong(27), Some(18));
    }

    #[test]
    fn test_positional_jamo_classification() {
        // 초성 U+1100 ~ U+1112
        assert!(is_choseong('\u{1100}'));
        assert!(is_choseong('\u{1112}'));
        assert!(!is_choseong('\u{1161}'));

        // 중성 U+1161 ~ U+1175
        assert!(is_jungseong('\u{1161}'));
        assert!(is_jungseong('\u{1175}'));
        assert!(!is_jungseong('\u{1100}'));

        // 종성 U+11A8 ~ U+11C2
        assert!(is_jongseong('\u{11A8}'));
        assert!(is_jongseong('\u{11C2}'));
        assert!(!is_jongseong('\u{1100}'));
    }

    #[test]
    fn test_is_syllable() {
        assert!(is_syllable('가'));
        assert!(is_syllable('힣'));
        assert!(is_syllable('한'));
        assert!(!is_syllable('ㄱ'));
        assert!(!is_syllable('A'));
    }

    // ── 경계값 테스트 ──

    #[test]
    fn test_compose_syllable_boundary() {
        // 각 인덱스의 경계: 최솟값
        assert_eq!(compose_syllable(0, 0, 0), Some('가'));
        // 각 인덱스의 경계: 최댓값
        assert_eq!(
            compose_syllable(L_COUNT - 1, V_COUNT - 1, T_COUNT - 1),
            Some('힣')
        );
        // 종성 없음 (t=0)
        assert_eq!(compose_syllable(0, 0, 0), Some('가'));
        // 종성 최대: 가 + 종성 27 = 갛 (U+AC1B)
        assert!(compose_syllable(0, 0, T_COUNT - 1).is_some());
        // 인덱스 범위 초과
        assert_eq!(compose_syllable(L_COUNT, 0, 0), None);
        assert_eq!(compose_syllable(0, V_COUNT, 0), None);
        assert_eq!(compose_syllable(0, 0, T_COUNT), None);
        assert_eq!(compose_syllable(u32::MAX, 0, 0), None);
        assert_eq!(compose_syllable(0, u32::MAX, 0), None);
        assert_eq!(compose_syllable(0, 0, u32::MAX), None);
    }

    #[test]
    fn test_decompose_syllable_boundary() {
        // 범위 직전 문자 (가 앞)
        assert_eq!(
            decompose_syllable(char::from_u32(S_BASE - 1).unwrap()),
            None
        );
        // 범위 직후 문자 (힣 뒤)
        assert_eq!(
            decompose_syllable(char::from_u32(S_BASE + S_COUNT).unwrap()),
            None
        );
        // 호환 자모는 음절이 아님
        assert_eq!(decompose_syllable('ㄱ'), None);
        assert_eq!(decompose_syllable('ㅏ'), None);
    }

    #[test]
    fn test_index_to_compat_out_of_range() {
        // 초성 범위 초과
        assert_eq!(choseong_to_compat(L_COUNT), None);
        assert_eq!(choseong_to_compat(u32::MAX), None);
        // 중성 범위 초과
        assert_eq!(jungseong_to_compat(V_COUNT), None);
        assert_eq!(jungseong_to_compat(u32::MAX), None);
        // 종성 범위 초과
        assert_eq!(jongseong_to_compat(T_COUNT), None);
        assert_eq!(jongseong_to_compat(u32::MAX), None);
        // 종성 0은 "종성 없음"
        assert_eq!(jongseong_to_compat(0), None);
    }

    #[test]
    fn test_jongseong_choseong_cross_conversion() {
        // 종성 불가 자음(ㄸ, ㅃ, ㅉ)은 초성→종성 변환 불가
        let l_dd = compat_to_choseong('ㄸ').unwrap(); // ㄸ 초성(4)
        assert_eq!(choseong_to_jongseong(l_dd), None);
        let l_bb = compat_to_choseong('ㅃ').unwrap(); // ㅃ 초성(8)
        assert_eq!(choseong_to_jongseong(l_bb), None);
        let l_jj = compat_to_choseong('ㅉ').unwrap(); // ㅉ 초성(13)
        assert_eq!(choseong_to_jongseong(l_jj), None);

        // 종성 0은 choseong 변환 불가
        assert_eq!(jongseong_to_choseong(0), None);
        // 겹종성(ㄳ=3)도 초성 변환 불가 (ㄳ은 초성에 없음)
        assert_eq!(jongseong_to_choseong(3), None);
    }

    #[test]
    fn test_split_double_jongseong_all() {
        // 모든 겹종성이 올바르게 분리되는지 확인
        let expected: &[(u32, u32, char)] = &[
            (3, 1, 'ㅅ'),   // ㄳ → ㄱ + ㅅ
            (5, 4, 'ㅈ'),   // ㄵ → ㄴ + ㅈ
            (6, 4, 'ㅎ'),   // ㄶ → ㄴ + ㅎ
            (9, 8, 'ㄱ'),   // ㄺ → ㄹ + ㄱ
            (10, 8, 'ㅁ'),  // ㄻ → ㄹ + ㅁ
            (11, 8, 'ㅂ'),  // ㄼ → ㄹ + ㅂ
            (12, 8, 'ㅅ'),  // ㄽ → ㄹ + ㅅ
            (13, 8, 'ㅌ'),  // ㄾ → ㄹ + ㅌ
            (14, 8, 'ㅍ'),  // ㄿ → ㄹ + ㅍ
            (15, 8, 'ㅎ'),  // ㅀ → ㄹ + ㅎ
            (18, 17, 'ㅅ'), // ㅄ → ㅂ + ㅅ
        ];
        for &(t, first, second) in expected {
            assert_eq!(split_double_jongseong(t), Some((first, second)));
            assert!(is_double_jongseong(t));
        }
        // 단일 종성은 겹종성이 아님
        for t in [1, 2, 4, 7, 8, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27] {
            assert_eq!(split_double_jongseong(t), None);
            assert!(!is_double_jongseong(t));
        }
    }

    #[test]
    fn test_split_double_jungseong_all() {
        // 모든 겹모음이 올바르게 분리되는지 확인
        let expected: &[(u32, u32, u32)] = &[
            (9, 8, 0),    // ㅘ → ㅗ + ㅏ
            (10, 8, 1),   // ㅙ → ㅗ + ㅐ
            (11, 8, 20),  // ㅚ → ㅗ + ㅣ
            (14, 13, 4),  // ㅝ → ㅜ + ㅓ
            (15, 13, 5),  // ㅞ → ㅜ + ㅔ
            (16, 13, 20), // ㅟ → ㅜ + ㅣ
            (19, 18, 20), // ㅢ → ㅡ + ㅣ
        ];
        for &(v, first, second) in expected {
            assert_eq!(split_double_jungseong(v), Some((first, second)));
            assert!(is_double_jungseong(v));
        }
        // 단일 모음은 겹모음이 아님
        for v in [0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13, 17, 18, 20] {
            assert_eq!(split_double_jungseong(v), None);
            assert!(!is_double_jungseong(v));
        }
    }

    #[test]
    fn test_positional_jamo_boundary() {
        // 초성 범위 바로 밖
        assert!(!is_choseong(char::from_u32(L_BASE - 1).unwrap()));
        assert!(!is_choseong(char::from_u32(L_BASE + L_COUNT).unwrap()));
        // 중성 범위 바로 밖
        assert!(!is_jungseong(char::from_u32(V_BASE - 1).unwrap()));
        assert!(!is_jungseong(char::from_u32(V_BASE + V_COUNT).unwrap()));
        // 종성 범위 바로 밖 (T_BASE 자체는 "종성 없음"이므로 종성 아님)
        assert!(!is_jongseong(char::from_u32(T_BASE).unwrap()));
        assert!(!is_jongseong(char::from_u32(T_BASE + T_COUNT).unwrap()));
    }

    #[test]
    fn test_positional_index_conversion() {
        // 초성 인덱스 변환
        assert_eq!(choseong_to_index('\u{1100}'), Some(0));
        assert_eq!(choseong_to_index('\u{1112}'), Some(18));
        assert_eq!(choseong_to_index('ㄱ'), None); // 호환 자모는 위치 자모가 아님
        // 중성 인덱스 변환
        assert_eq!(jungseong_to_index('\u{1161}'), Some(0));
        assert_eq!(jungseong_to_index('\u{1175}'), Some(20));
        assert_eq!(jungseong_to_index('ㅏ'), None);
        // 종성 인덱스 변환
        assert_eq!(jongseong_to_index('\u{11A8}'), Some(1));
        assert_eq!(jongseong_to_index('\u{11C2}'), Some(27));
        assert_eq!(jongseong_to_index('ㄱ'), None);
    }

    #[test]
    fn test_is_korean_jamo_comprehensive() {
        // 위치 자모
        assert!(is_korean_jamo('\u{1100}')); // 위치 초성 ㄱ
        assert!(is_korean_jamo('\u{1161}')); // 위치 중성 ㅏ
        assert!(is_korean_jamo('\u{11A8}')); // 위치 종성 ㄱ
        // 호환 자모
        assert!(is_korean_jamo('ㄱ'));
        assert!(is_korean_jamo('ㅏ'));
        // 비자모
        assert!(!is_korean_jamo('가')); // 완성형 음절
        assert!(!is_korean_jamo('A'));
        assert!(!is_korean_jamo('1'));
        assert!(!is_korean_jamo(' '));
    }
}
