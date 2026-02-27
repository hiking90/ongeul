//! 세벌식(3-beolsik) 오토마타
//!
//! 3슬롯 채우기 방식: 초성/중성/종성이 별도 키로 구분됨.
//! 종성 분리 불필요, auto_reorder 선택적 지원.

use crate::layout::KeyboardLayout;
use crate::unicode;

use super::{Automata, AutomataResult, AutomataState, ComposeBuffer};

/// 세벌식 오토마타
pub struct JasoAutomata {
    buffer: ComposeBuffer,
    /// 쌍자음 초성 백스페이스 복원용
    prev_choseong: Option<u32>,
    /// 겹모음 백스페이스 복원용
    prev_jungseong: Option<u32>,
    /// 겹종성 백스페이스 복원용
    prev_jongseong: Option<u32>,
}

impl Default for JasoAutomata {
    fn default() -> Self {
        Self::new()
    }
}

impl JasoAutomata {
    pub fn new() -> Self {
        JasoAutomata {
            buffer: ComposeBuffer::new(),
            prev_choseong: None,
            prev_jungseong: None,
            prev_jongseong: None,
        }
    }

    fn commit_current(&mut self) -> Option<String> {
        let text = self.buffer.to_string();
        self.buffer.reset();
        self.prev_choseong = None;
        self.prev_jungseong = None;
        self.prev_jongseong = None;
        text
    }

    /// 자모의 위치(초/중/종)를 분류한다.
    fn classify(ch: char) -> JasoClass {
        if unicode::is_choseong(ch) {
            JasoClass::Choseong(ch as u32 - unicode::L_BASE)
        } else if unicode::is_jungseong(ch) {
            JasoClass::Jungseong(ch as u32 - unicode::V_BASE)
        } else if unicode::is_jongseong(ch) {
            JasoClass::Jongseong(ch as u32 - unicode::T_BASE)
        } else {
            JasoClass::Unknown
        }
    }

    /// 초성 인덱스를 위치 자모 char로 변환
    fn l_char(idx: u32) -> char {
        char::from_u32(unicode::L_BASE + idx).unwrap()
    }

    /// 중성 인덱스를 위치 자모 char로 변환
    fn v_char(idx: u32) -> char {
        char::from_u32(unicode::V_BASE + idx).unwrap()
    }

    /// 종성 인덱스를 위치 자모 char로 변환
    fn t_char(idx: u32) -> char {
        char::from_u32(unicode::T_BASE + idx).unwrap()
    }
}

#[derive(Debug)]
enum JasoClass {
    Choseong(u32),
    Jungseong(u32),
    Jongseong(u32),
    Unknown,
}

impl Automata for JasoAutomata {
    fn process(&mut self, ch: char, layout: &KeyboardLayout) -> AutomataResult {
        let class = Self::classify(ch);

        match class {
            JasoClass::Unknown => {
                if self.buffer.state != AutomataState::Empty {
                    let committed = self.commit_current();
                    return AutomataResult::handled(committed, None);
                }
                AutomataResult::not_handled()
            }
            JasoClass::Choseong(l_idx) => {
                if let Some(current_l) = self.buffer.choseong {
                    // 중성이 이미 있으면 음절 진행 중 → 확정 + 새 초성
                    if self.buffer.jungseong.is_some() {
                        let committed = self.commit_current();
                        self.buffer.choseong = Some(l_idx);
                        self.buffer.state = AutomataState::Choseong;
                        return AutomataResult::handled(committed, self.buffer.to_string());
                    }
                    // 초성만 있음 → 쌍자음 조합 시도
                    let current_ch = Self::l_char(current_l);
                    let new_ch = Self::l_char(l_idx);
                    if let Some(combined) = layout.combine(current_ch, new_ch)
                        && let Some(combined_idx) = unicode::choseong_to_index(combined)
                    {
                        self.prev_choseong = Some(current_l);
                        self.buffer.choseong = Some(combined_idx);
                        return AutomataResult::handled(None, self.buffer.to_string());
                    }
                    // 쌍자음 불가 → 확정 + 새 초성
                    let committed = self.commit_current();
                    self.buffer.choseong = Some(l_idx);
                    self.buffer.state = AutomataState::Choseong;
                    AutomataResult::handled(committed, self.buffer.to_string())
                } else {
                    self.buffer.choseong = Some(l_idx);
                    self.buffer.state = AutomataState::Choseong;
                    AutomataResult::handled(None, self.buffer.to_string())
                }
            }
            JasoClass::Jungseong(v_idx) => {
                if let Some(current_v) = self.buffer.jungseong {
                    // 이미 중성 있음 → 겹모음 시도 (위치 자모로 조합)
                    let current_ch = Self::v_char(current_v);
                    let new_ch = Self::v_char(v_idx);
                    if let Some(combined) = layout.combine(current_ch, new_ch)
                        && let Some(combined_idx) = unicode::jungseong_to_index(combined)
                    {
                        self.prev_jungseong = Some(current_v);
                        self.buffer.jungseong = Some(combined_idx);
                        self.buffer.state = AutomataState::Jungseong2;
                        return AutomataResult::handled(None, self.buffer.to_string());
                    }
                    // 겹모음 불가 → 확정 + 새 조합
                    let committed = self.commit_current();
                    self.buffer.jungseong = Some(v_idx);
                    self.buffer.state = AutomataState::Jungseong;
                    AutomataResult::handled(committed, self.buffer.to_string())
                } else {
                    self.buffer.jungseong = Some(v_idx);
                    self.buffer.state = AutomataState::Jungseong;
                    AutomataResult::handled(None, self.buffer.to_string())
                }
            }
            JasoClass::Jongseong(t_idx) => {
                if self.buffer.choseong.is_none() || self.buffer.jungseong.is_none() {
                    // 초성+중성이 없으면 종성 독립 불가 → 즉시 확정
                    let mut committed = if self.buffer.state != AutomataState::Empty {
                        self.commit_current().unwrap_or_default()
                    } else {
                        String::new()
                    };
                    if let Some(ch) = unicode::jongseong_to_compat(t_idx) {
                        committed.push(ch);
                    }
                    return AutomataResult::handled(Some(committed), None);
                }

                if let Some(current_t) = self.buffer.jongseong {
                    // 이미 종성 있음 → 겹종성 시도 (위치 자모로 조합)
                    let current_ch = Self::t_char(current_t);
                    let new_ch = Self::t_char(t_idx);
                    if let Some(combined) = layout.combine(current_ch, new_ch)
                        && let Some(combined_idx) = unicode::jongseong_to_index(combined)
                    {
                        self.prev_jongseong = Some(current_t);
                        self.buffer.jongseong = Some(combined_idx);
                        self.buffer.state = AutomataState::Jongseong2;
                        return AutomataResult::handled(None, self.buffer.to_string());
                    }
                    // 겹종성 불가 → 현재 음절 + 독립 종성 모두 즉시 확정
                    let mut committed = self.commit_current().unwrap_or_default();
                    if let Some(ch) = unicode::jongseong_to_compat(t_idx) {
                        committed.push(ch);
                    }
                    AutomataResult::handled(Some(committed), None)
                } else {
                    self.buffer.jongseong = Some(t_idx);
                    self.buffer.state = AutomataState::Jongseong;
                    AutomataResult::handled(None, self.buffer.to_string())
                }
            }
        }
    }

    fn backspace(&mut self) -> AutomataResult {
        match self.buffer.state {
            AutomataState::Empty => AutomataResult::not_handled(),
            AutomataState::Jongseong2 => {
                if let Some(prev_t) = self.prev_jongseong {
                    self.buffer.jongseong = Some(prev_t);
                    self.prev_jongseong = None;
                    self.buffer.state = AutomataState::Jongseong;
                }
                AutomataResult::handled(None, self.buffer.to_string())
            }
            AutomataState::Jongseong => {
                self.buffer.jongseong = None;
                self.prev_jongseong = None;
                if self.prev_jungseong.is_some() {
                    self.buffer.state = AutomataState::Jungseong2;
                } else if self.buffer.jungseong.is_some() {
                    self.buffer.state = AutomataState::Jungseong;
                } else if self.buffer.choseong.is_some() {
                    self.buffer.state = AutomataState::Choseong;
                } else {
                    self.buffer.state = AutomataState::Empty;
                }
                AutomataResult::handled(None, self.buffer.to_string())
            }
            AutomataState::Jungseong2 => {
                if let Some(prev_v) = self.prev_jungseong {
                    self.buffer.jungseong = Some(prev_v);
                    self.prev_jungseong = None;
                    self.buffer.state = AutomataState::Jungseong;
                }
                AutomataResult::handled(None, self.buffer.to_string())
            }
            AutomataState::Jungseong => {
                self.buffer.jungseong = None;
                self.prev_jungseong = None;
                if self.buffer.choseong.is_some() {
                    self.buffer.state = AutomataState::Choseong;
                } else {
                    self.buffer.state = AutomataState::Empty;
                }
                AutomataResult::handled(None, self.buffer.to_string())
            }
            AutomataState::Choseong => {
                // 쌍자음이었다면 원래 초성으로 복원
                if let Some(prev_l) = self.prev_choseong {
                    self.buffer.choseong = Some(prev_l);
                    self.prev_choseong = None;
                    return AutomataResult::handled(None, self.buffer.to_string());
                }
                self.buffer.reset();
                self.prev_choseong = None;
                self.prev_jungseong = None;
                self.prev_jongseong = None;
                AutomataResult::handled(None, None)
            }
        }
    }

    fn flush(&mut self) -> AutomataResult {
        if self.buffer.state == AutomataState::Empty {
            return AutomataResult::handled(None, None);
        }
        let committed = self.commit_current();
        AutomataResult::handled(committed, None)
    }

    fn composing_text(&self) -> Option<String> {
        self.buffer.to_string()
    }

    fn state(&self) -> AutomataState {
        self.buffer.state
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::KeyboardLayout;

    const LAYOUT_390_JSON: &str = include_str!("../../layouts/3-390.json5");

    fn make_layout() -> KeyboardLayout {
        KeyboardLayout::from_json(LAYOUT_390_JSON).unwrap()
    }

    fn process_keys(
        automata: &mut JasoAutomata,
        layout: &KeyboardLayout,
        keys: &[&str],
    ) -> (String, Option<String>) {
        let mut committed = String::new();
        let mut composing = None;
        for key in keys {
            let ch = layout.map_key(key).unwrap();
            let result = automata.process(ch, layout);
            if let Some(c) = &result.committed {
                committed.push_str(c);
            }
            composing = result.composing;
        }
        (committed, composing)
    }

    #[test]
    fn test_basic_syllable() {
        // ㅎ(초) + ㅏ(중) + ㄴ(종) → "한"
        // 세벌식390: m=ㅎ초, f=ㅏ중, s=ㄴ종
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["m", "f", "s"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("한".to_string()));
    }

    #[test]
    fn test_hangul_word() {
        // "한글" = ㅎ초 ㅏ중 ㄴ종 ㄱ초 ㅡ중 ㄹ종
        // 세벌식390: m f s k g w
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["m", "f", "s", "k", "g", "w"]);
        assert_eq!(committed, "한");
        assert_eq!(composing, Some("글".to_string()));
    }

    #[test]
    fn test_no_jongseong() {
        // ㄱ초 + ㅏ중 → "가"
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["k", "f"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("가".to_string()));
    }

    #[test]
    fn test_double_vowel() {
        // ㄱ초 + ㅗ중 + ㅏ중 → "과" (겹모음 ㅘ)
        // v=ㅗ, f=ㅏ
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["k", "v", "f"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("과".to_string()));
    }

    #[test]
    fn test_double_jongseong() {
        // ㄱ초 + ㅏ중 + ㄹ종 + ㄱ종 → "갉" (겹종성 ㄺ)
        // k=ㄱ초, f=ㅏ중, w=ㄹ종, x=ㄱ종
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["k", "f", "w", "x"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("갉".to_string()));
    }

    #[test]
    fn test_ssang_choseong() {
        // ㄱ초 + ㄱ초 → ㄲ초 (쌍자음 조합)
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let ch1 = layout.map_key("k").unwrap(); // ㄱ초
        let result = automata.process(ch1, &layout);
        assert_eq!(result.composing, Some("ㄱ".to_string()));

        let ch2 = layout.map_key("k").unwrap(); // ㄱ초
        let result = automata.process(ch2, &layout);
        assert_eq!(result.committed, None);
        assert_eq!(result.composing, Some("ㄲ".to_string()));
    }

    #[test]
    fn test_ssang_choseong_with_vowel() {
        // ㄱ초 + ㄱ초 + ㅏ중 → "까"
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["k", "k", "f"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("까".to_string()));
    }

    #[test]
    fn test_backspace_from_jongseong() {
        // ㅎ초 ㅏ중 ㄴ종 + BS → "하"
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        process_keys(&mut automata, &layout, &["m", "f", "s"]);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("하".to_string()));
    }

    #[test]
    fn test_backspace_from_double_jongseong() {
        // ㄱ초 ㅏ중 ㄹ종 ㄱ종 + BS → "갈"
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        process_keys(&mut automata, &layout, &["k", "f", "w", "x"]);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("갈".to_string()));
    }

    #[test]
    fn test_backspace_from_double_vowel() {
        // ㄱ초 ㅗ중 ㅏ중 + BS → "고"
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        process_keys(&mut automata, &layout, &["k", "v", "f"]);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("고".to_string()));
    }

    #[test]
    fn test_backspace_from_ssang_choseong() {
        // ㄱ초 ㄱ초 + BS → "ㄱ"
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        process_keys(&mut automata, &layout, &["k", "k"]);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("ㄱ".to_string()));
    }

    #[test]
    fn test_backspace_to_empty() {
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        process_keys(&mut automata, &layout, &["k"]);
        let result = automata.backspace();
        assert_eq!(result.composing, None);
        assert!(result.handled);

        let result = automata.backspace();
        assert!(!result.handled);
    }

    #[test]
    fn test_flush() {
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        process_keys(&mut automata, &layout, &["m", "f", "s"]);
        let result = automata.flush();
        assert_eq!(result.committed, Some("한".to_string()));
        assert_eq!(result.composing, None);
    }

    #[test]
    fn test_choseong_after_complete_syllable() {
        // "된" + ㄷ초 → committed="된", composing="ㄷ" (쌍자음 안 됨)
        // ㄷ초(u) ㅗ중(v) ㅣ중(d) ㄴ종(s) ㄷ초(u)
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["u", "v", "d", "s", "u"]);
        assert_eq!(committed, "된");
        assert_eq!(composing, Some("ㄷ".to_string()));
    }

    #[test]
    fn test_consecutive_syllables() {
        // "나라" = ㄴ초 ㅏ중 ㄹ초 ㅏ중
        // h=ㄴ초, f=ㅏ중, y=ㄹ초, f=ㅏ중
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["h", "f", "y", "f"]);
        assert_eq!(committed, "나");
        assert_eq!(composing, Some("라".to_string()));
    }

    #[test]
    fn test_jongseong_without_choseong_jungseong() {
        // 종성만 입력 → 즉시 확정 (composing 없음)
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let ch = layout.map_key("q").unwrap(); // ㅅ종
        let result = automata.process(ch, &layout);
        assert_eq!(result.committed, Some("ㅅ".to_string()));
        assert_eq!(result.composing, None);
    }

    #[test]
    fn test_standalone_jongseong_then_choseong() {
        // ㅅ종 → ㄱ초 → "ㅅ" 확정 + "ㄱ" 조합 (데이터 소실 없음)
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["q", "k"]);
        assert_eq!(committed, "ㅅ");
        assert_eq!(composing, Some("ㄱ".to_string()));
    }

    #[test]
    fn test_eui_combination() {
        // ㅡ + ㅣ = ㅢ
        // ㅇ초(j) + ㅡ중(g) + ㅣ중(d) → "의"
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["j", "g", "d"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("의".to_string()));
    }

    #[test]
    fn test_ssang_jongseong() {
        // ㄱ초 + ㅏ중 + ㅅ종 + ㅅ종 → ㅆ종 (종성 쌍자음)
        // k=ㄱ초, f=ㅏ중, q=ㅅ종, q=ㅅ종
        let layout = make_layout();
        let mut automata = JasoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["k", "f", "q", "q"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("갔".to_string()));
    }
}
