//! 두벌식(2-beolsik) 오토마타
//!
//! 6개 상태 전이: Empty → Choseong → Jungseong → Jungseong2 → Jongseong → Jongseong2
//! 핵심: 종성 분리, 겹종성 분리, 백스페이스 역방향 처리

use crate::layout::KeyboardLayout;
use crate::unicode;

use super::{Automata, AutomataResult, AutomataState, ComposeBuffer};

/// 두벌식 오토마타
pub struct JamoAutomata {
    buffer: ComposeBuffer,
    /// 겹모음 상태에서 백스페이스 시 원래 모음을 복원하기 위한 저장값
    prev_jungseong: Option<u32>,
    /// 겹종성 상태에서 백스페이스 시 원래 종성을 복원하기 위한 저장값
    prev_jongseong: Option<u32>,
}

impl Default for JamoAutomata {
    fn default() -> Self {
        Self::new()
    }
}

impl JamoAutomata {
    pub fn new() -> Self {
        JamoAutomata {
            buffer: ComposeBuffer::new(),
            prev_jungseong: None,
            prev_jongseong: None,
        }
    }

    /// 현재 버퍼의 조합 문자열을 확정 텍스트로 반환하고 리셋한다.
    fn commit_current(&mut self) -> Option<String> {
        let text = self.buffer.to_string();
        self.buffer.reset();
        self.prev_jungseong = None;
        self.prev_jongseong = None;
        text
    }

    /// S0(Empty) + 자음 → S1(Choseong)
    fn process_empty_consonant(&mut self, l_idx: u32) -> AutomataResult {
        self.buffer.choseong = Some(l_idx);
        self.buffer.state = AutomataState::Choseong;
        AutomataResult::handled(None, self.buffer.to_string())
    }

    /// S0(Empty) + 모음 → S2(Jungseong) — 초성 없이 모음만
    fn process_empty_vowel(&mut self, v_idx: u32) -> AutomataResult {
        self.buffer.jungseong = Some(v_idx);
        self.buffer.state = AutomataState::Jungseong;
        AutomataResult::handled(None, self.buffer.to_string())
    }

    /// S1(Choseong) + 모음 → S2(Jungseong)
    fn process_choseong_vowel(&mut self, v_idx: u32) -> AutomataResult {
        self.buffer.jungseong = Some(v_idx);
        self.buffer.state = AutomataState::Jungseong;
        AutomataResult::handled(None, self.buffer.to_string())
    }

    /// S1(Choseong) + 자음 → 현재 확정 + 새 S1(Choseong)
    fn process_choseong_consonant(&mut self, l_idx: u32) -> AutomataResult {
        let committed = self.commit_current();
        self.buffer.choseong = Some(l_idx);
        self.buffer.state = AutomataState::Choseong;
        AutomataResult::handled(committed, self.buffer.to_string())
    }

    /// S2(Jungseong) + 모음: 겹모음 가능하면 S3, 아니면 확정 + 새 모음
    fn process_jungseong_vowel(
        &mut self,
        v_idx: u32,
        layout: &KeyboardLayout,
    ) -> AutomataResult {
        let current_v = self.buffer.jungseong.unwrap();
        let current_v_ch = unicode::jungseong_to_compat(current_v).unwrap();
        let new_v_ch = unicode::jungseong_to_compat(v_idx).unwrap();

        if let Some(combined) = layout.combine(current_v_ch, new_v_ch)
            && let Some(combined_idx) = unicode::compat_to_jungseong(combined)
        {
            self.prev_jungseong = Some(current_v);
            self.buffer.jungseong = Some(combined_idx);
            self.buffer.state = AutomataState::Jungseong2;
            return AutomataResult::handled(None, self.buffer.to_string());
        }

        // 겹모음 불가 → 현재 확정, 새 모음 시작
        let committed = self.commit_current();
        self.buffer.jungseong = Some(v_idx);
        self.buffer.state = AutomataState::Jungseong;
        AutomataResult::handled(committed, self.buffer.to_string())
    }

    /// S2(Jungseong) + 자음: 종성 가능하면 S4, 불가면 확정 + 새 초성
    fn process_jungseong_consonant(&mut self, ch: char, l_idx: u32) -> AutomataResult {
        // 초성이 없으면(모음만 입력된 상태) 종성 불가 → 확정 + 새 초성
        if self.buffer.choseong.is_none() {
            let committed = self.commit_current();
            self.buffer.choseong = Some(l_idx);
            self.buffer.state = AutomataState::Choseong;
            return AutomataResult::handled(committed, self.buffer.to_string());
        }

        if unicode::is_jongseong_impossible(ch) {
            // 종성 불가 자음 → 현재 확정, 새 초성
            let committed = self.commit_current();
            self.buffer.choseong = Some(l_idx);
            self.buffer.state = AutomataState::Choseong;
            return AutomataResult::handled(committed, self.buffer.to_string());
        }

        if let Some(t_idx) = unicode::compat_to_jongseong(ch) {
            self.buffer.jongseong = Some(t_idx);
            self.buffer.state = AutomataState::Jongseong;
            AutomataResult::handled(None, self.buffer.to_string())
        } else {
            // 종성 매핑 없음 → 확정 + 새 초성
            let committed = self.commit_current();
            self.buffer.choseong = Some(l_idx);
            self.buffer.state = AutomataState::Choseong;
            AutomataResult::handled(committed, self.buffer.to_string())
        }
    }

    /// S3(Jungseong2) + 자음: 종성 가능하면 S4, 불가면 확정 + 새 초성
    fn process_jungseong2_consonant(&mut self, ch: char, l_idx: u32) -> AutomataResult {
        // 초성 없으면 확정 + 새 초성
        if self.buffer.choseong.is_none() {
            let committed = self.commit_current();
            self.buffer.choseong = Some(l_idx);
            self.buffer.state = AutomataState::Choseong;
            return AutomataResult::handled(committed, self.buffer.to_string());
        }

        if unicode::is_jongseong_impossible(ch) {
            let committed = self.commit_current();
            self.buffer.choseong = Some(l_idx);
            self.buffer.state = AutomataState::Choseong;
            return AutomataResult::handled(committed, self.buffer.to_string());
        }

        if let Some(t_idx) = unicode::compat_to_jongseong(ch) {
            self.buffer.jongseong = Some(t_idx);
            self.buffer.state = AutomataState::Jongseong;
            AutomataResult::handled(None, self.buffer.to_string())
        } else {
            let committed = self.commit_current();
            self.buffer.choseong = Some(l_idx);
            self.buffer.state = AutomataState::Choseong;
            AutomataResult::handled(committed, self.buffer.to_string())
        }
    }

    /// S4(Jongseong) + 자음: 겹종성 가능하면 S5, 아니면 확정 + 새 초성
    fn process_jongseong_consonant(
        &mut self,
        ch: char,
        l_idx: u32,
        layout: &KeyboardLayout,
    ) -> AutomataResult {
        let current_t = self.buffer.jongseong.unwrap();
        let current_t_ch = unicode::jongseong_to_compat(current_t).unwrap();

        // 겹종성 조합 시도
        if let Some(combined) = layout.combine(current_t_ch, ch)
            && let Some(combined_idx) = unicode::compat_to_jongseong(combined)
        {
            self.prev_jongseong = Some(current_t);
            self.buffer.jongseong = Some(combined_idx);
            self.buffer.state = AutomataState::Jongseong2;
            return AutomataResult::handled(None, self.buffer.to_string());
        }

        // 겹종성 불가 → 현재 확정, 새 초성
        let committed = self.commit_current();
        self.buffer.choseong = Some(l_idx);
        self.buffer.state = AutomataState::Choseong;
        AutomataResult::handled(committed, self.buffer.to_string())
    }

    /// S4(Jongseong) + 모음: ★종성 분리★
    /// 종성을 다음 초성으로 이동, 현재 LV를 확정
    fn process_jongseong_vowel(&mut self, v_idx: u32) -> AutomataResult {
        let t = self.buffer.jongseong.unwrap();
        let l = self.buffer.choseong.unwrap();
        let v = self.buffer.jungseong.unwrap();

        // 종성을 초성으로 변환
        let next_l = unicode::jongseong_to_choseong(t).unwrap();

        // 현재 음절을 종성 없이 확정
        let committed = unicode::compose_syllable(l, v, 0)
            .map(|ch| ch.to_string());

        // 새 음절: 이전 종성이 초성 + 새 모음
        self.buffer.reset();
        self.prev_jungseong = None;
        self.prev_jongseong = None;
        self.buffer.choseong = Some(next_l);
        self.buffer.jungseong = Some(v_idx);
        self.buffer.state = AutomataState::Jungseong;

        AutomataResult::handled(committed, self.buffer.to_string())
    }

    /// S5(Jongseong2) + 모음: ★겹종성 분리★
    /// 겹종성 분리, 첫째 유지, 둘째를 다음 초성으로 이동
    fn process_jongseong2_vowel(&mut self, v_idx: u32) -> AutomataResult {
        let t = self.buffer.jongseong.unwrap();
        let l = self.buffer.choseong.unwrap();
        let v = self.buffer.jungseong.unwrap();

        // 겹종성 분리
        let (first_t, second_ch) = unicode::split_double_jongseong(t).unwrap();
        let next_l = unicode::compat_to_choseong(second_ch).unwrap();

        // 현재 음절: 첫째 종성만 유지하고 확정
        let committed = unicode::compose_syllable(l, v, first_t)
            .map(|ch| ch.to_string());

        // 새 음절: 둘째 자모가 초성 + 새 모음
        self.buffer.reset();
        self.prev_jungseong = None;
        self.prev_jongseong = None;
        self.buffer.choseong = Some(next_l);
        self.buffer.jungseong = Some(v_idx);
        self.buffer.state = AutomataState::Jungseong;

        AutomataResult::handled(committed, self.buffer.to_string())
    }

    /// S5(Jongseong2) + 자음 → 현재 확정, 새 초성
    fn process_jongseong2_consonant(&mut self, l_idx: u32) -> AutomataResult {
        let committed = self.commit_current();
        self.buffer.choseong = Some(l_idx);
        self.buffer.state = AutomataState::Choseong;
        AutomataResult::handled(committed, self.buffer.to_string())
    }
}

impl Automata for JamoAutomata {
    fn process(&mut self, ch: char, layout: &KeyboardLayout) -> AutomataResult {
        let is_consonant = unicode::is_compat_consonant(ch);
        let is_vowel = unicode::is_compat_vowel(ch);

        if !is_consonant && !is_vowel {
            // 한글이 아닌 입력 → 현재 조합 확정 후 패스스루
            if self.buffer.state != AutomataState::Empty {
                let committed = self.commit_current();
                return AutomataResult::handled(committed, None);
            }
            return AutomataResult::not_handled();
        }

        match self.buffer.state {
            AutomataState::Empty => {
                if is_consonant {
                    let l_idx = unicode::compat_to_choseong(ch).unwrap();
                    self.process_empty_consonant(l_idx)
                } else {
                    let v_idx = unicode::compat_to_jungseong(ch).unwrap();
                    self.process_empty_vowel(v_idx)
                }
            }
            AutomataState::Choseong => {
                if is_vowel {
                    let v_idx = unicode::compat_to_jungseong(ch).unwrap();
                    self.process_choseong_vowel(v_idx)
                } else {
                    let l_idx = unicode::compat_to_choseong(ch).unwrap();
                    self.process_choseong_consonant(l_idx)
                }
            }
            AutomataState::Jungseong => {
                if is_vowel {
                    let v_idx = unicode::compat_to_jungseong(ch).unwrap();
                    self.process_jungseong_vowel(v_idx, layout)
                } else {
                    let l_idx = unicode::compat_to_choseong(ch).unwrap();
                    self.process_jungseong_consonant(ch, l_idx)
                }
            }
            AutomataState::Jungseong2 => {
                if is_vowel {
                    // 겹모음 상태에서 또 모음 → 현재 확정 + 새 모음
                    let committed = self.commit_current();
                    let v_idx = unicode::compat_to_jungseong(ch).unwrap();
                    self.buffer.jungseong = Some(v_idx);
                    self.buffer.state = AutomataState::Jungseong;
                    AutomataResult::handled(committed, self.buffer.to_string())
                } else {
                    let l_idx = unicode::compat_to_choseong(ch).unwrap();
                    self.process_jungseong2_consonant(ch, l_idx)
                }
            }
            AutomataState::Jongseong => {
                if is_vowel {
                    let v_idx = unicode::compat_to_jungseong(ch).unwrap();
                    self.process_jongseong_vowel(v_idx)
                } else {
                    let l_idx = unicode::compat_to_choseong(ch).unwrap();
                    self.process_jongseong_consonant(ch, l_idx, layout)
                }
            }
            AutomataState::Jongseong2 => {
                if is_vowel {
                    let v_idx = unicode::compat_to_jungseong(ch).unwrap();
                    self.process_jongseong2_vowel(v_idx)
                } else {
                    let l_idx = unicode::compat_to_choseong(ch).unwrap();
                    self.process_jongseong2_consonant(l_idx)
                }
            }
        }
    }

    fn backspace(&mut self) -> AutomataResult {
        match self.buffer.state {
            AutomataState::Empty => {
                // 조합 없음 → 시스템에 위임
                AutomataResult::not_handled()
            }
            AutomataState::Choseong => {
                // S1 → S0: 초성 제거
                self.buffer.reset();
                self.prev_jungseong = None;
                self.prev_jongseong = None;
                AutomataResult::handled(None, None)
            }
            AutomataState::Jungseong => {
                if self.buffer.choseong.is_some() {
                    // 초성+중성 → 초성만
                    self.buffer.jungseong = None;
                    self.buffer.state = AutomataState::Choseong;
                } else {
                    // 중성만 → Empty
                    self.buffer.reset();
                }
                self.prev_jungseong = None;
                AutomataResult::handled(None, self.buffer.to_string())
            }
            AutomataState::Jungseong2 => {
                // S3 → S2: 겹모음의 두 번째 제거, 첫 번째 모음으로 복원
                if let Some(prev_v) = self.prev_jungseong {
                    self.buffer.jungseong = Some(prev_v);
                    self.prev_jungseong = None;
                    self.buffer.state = AutomataState::Jungseong;
                }
                AutomataResult::handled(None, self.buffer.to_string())
            }
            AutomataState::Jongseong => {
                // S4 → S2 or S3: 종성 제거
                self.buffer.jongseong = None;
                self.prev_jongseong = None;
                // 겹모음이었다면 Jungseong2, 아니면 Jungseong
                if self.prev_jungseong.is_some() {
                    self.buffer.state = AutomataState::Jungseong2;
                } else {
                    self.buffer.state = AutomataState::Jungseong;
                }
                AutomataResult::handled(None, self.buffer.to_string())
            }
            AutomataState::Jongseong2 => {
                // S5 → S4: 겹종성의 두 번째 자음 제거
                if let Some(prev_t) = self.prev_jongseong {
                    self.buffer.jongseong = Some(prev_t);
                    self.prev_jongseong = None;
                    self.buffer.state = AutomataState::Jongseong;
                }
                AutomataResult::handled(None, self.buffer.to_string())
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

    /// 두벌식 테스트용 최소 레이아웃 JSON
    const TEST_LAYOUT_JSON: &str = r#"{
        id: "2-standard-test",
        name: "두벌식 테스트",
        type: "jamo",
        keymap: {
            "r": "0x3131",  // ㄱ
            "R": "0x3132",  // ㄲ
            "s": "0x3134",  // ㄴ
            "e": "0x3137",  // ㄷ
            "E": "0x3138",  // ㄸ
            "f": "0x3139",  // ㄹ
            "a": "0x3141",  // ㅁ
            "q": "0x3142",  // ㅂ
            "Q": "0x3143",  // ㅃ
            "t": "0x3145",  // ㅅ
            "T": "0x3146",  // ㅆ
            "d": "0x3147",  // ㅇ
            "w": "0x3148",  // ㅈ
            "W": "0x3149",  // ㅉ
            "c": "0x314A",  // ㅊ
            "z": "0x314B",  // ㅋ
            "x": "0x314C",  // ㅌ
            "v": "0x314D",  // ㅍ
            "g": "0x314E",  // ㅎ

            "k": "0x314F",  // ㅏ
            "o": "0x3150",  // ㅐ
            "i": "0x3151",  // ㅑ
            "O": "0x3152",  // ㅒ
            "j": "0x3153",  // ㅓ
            "p": "0x3154",  // ㅔ
            "u": "0x3155",  // ㅕ
            "P": "0x3156",  // ㅖ
            "h": "0x3157",  // ㅗ
            "y": "0x315B",  // ㅛ
            "n": "0x315C",  // ㅜ
            "b": "0x3160",  // ㅠ
            "m": "0x3161",  // ㅡ
            "l": "0x3163",  // ㅣ
        },
        combinations: [
            // 겹모음
            { first: "0x3157", second: "0x314F", result: "0x3158" },  // ㅗ + ㅏ = ㅘ
            { first: "0x3157", second: "0x3150", result: "0x3159" },  // ㅗ + ㅐ = ㅙ
            { first: "0x3157", second: "0x3163", result: "0x315A" },  // ㅗ + ㅣ = ㅚ
            { first: "0x315C", second: "0x3153", result: "0x315D" },  // ㅜ + ㅓ = ㅝ
            { first: "0x315C", second: "0x3154", result: "0x315E" },  // ㅜ + ㅔ = ㅞ
            { first: "0x315C", second: "0x3163", result: "0x315F" },  // ㅜ + ㅣ = ㅟ
            { first: "0x3161", second: "0x3163", result: "0x3162" },  // ㅡ + ㅣ = ㅢ
            // 겹받침
            { first: "0x3131", second: "0x3145", result: "0x3133" },  // ㄱ + ㅅ = ㄳ
            { first: "0x3134", second: "0x3148", result: "0x3135" },  // ㄴ + ㅈ = ㄵ
            { first: "0x3134", second: "0x314E", result: "0x3136" },  // ㄴ + ㅎ = ㄶ
            { first: "0x3139", second: "0x3131", result: "0x313A" },  // ㄹ + ㄱ = ㄺ
            { first: "0x3139", second: "0x3141", result: "0x313B" },  // ㄹ + ㅁ = ㄻ
            { first: "0x3139", second: "0x3142", result: "0x313C" },  // ㄹ + ㅂ = ㄼ
            { first: "0x3139", second: "0x3145", result: "0x313D" },  // ㄹ + ㅅ = ㄽ
            { first: "0x3139", second: "0x314C", result: "0x313E" },  // ㄹ + ㅌ = ㄾ
            { first: "0x3139", second: "0x314D", result: "0x313F" },  // ㄹ + ㅍ = ㄿ
            { first: "0x3139", second: "0x314E", result: "0x3140" },  // ㄹ + ㅎ = ㅀ
            { first: "0x3142", second: "0x3145", result: "0x3144" },  // ㅂ + ㅅ = ㅄ
        ],
    }"#;

    fn make_layout() -> KeyboardLayout {
        KeyboardLayout::from_json(TEST_LAYOUT_JSON).unwrap()
    }

    /// 키 시퀀스를 처리하고 (committed 누적, 최종 composing) 반환
    fn process_keys(
        automata: &mut JamoAutomata,
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
    fn test_single_consonant() {
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let ch = layout.map_key("r").unwrap(); // ㄱ
        let result = automata.process(ch, &layout);
        assert_eq!(result.composing, Some("ㄱ".to_string()));
        assert_eq!(result.committed, None);
        assert_eq!(automata.state(), AutomataState::Choseong);
    }

    #[test]
    fn test_consonant_vowel() {
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["r", "k"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("가".to_string()));
        assert_eq!(automata.state(), AutomataState::Jungseong);
    }

    #[test]
    fn test_full_syllable_han() {
        // ㅎ ㅏ ㄴ → 한
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) = process_keys(&mut automata, &layout, &["g", "k", "s"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("한".to_string()));
        assert_eq!(automata.state(), AutomataState::Jongseong);
    }

    #[test]
    fn test_hangul_word() {
        // ㅎ ㅏ ㄴ ㄱ ㅡ ㄹ → "한" 확정 + "글" 조합
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["g", "k", "s", "r", "m", "f"]);
        assert_eq!(committed, "한");
        assert_eq!(composing, Some("글".to_string()));
    }

    #[test]
    fn test_jongseong_split() {
        // ㄱ ㅏ ㄴ ㅕ → "가" 확정 + "녀" 조합 (종성 분리)
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["r", "k", "s", "u"]);
        assert_eq!(committed, "가");
        assert_eq!(composing, Some("녀".to_string()));
    }

    #[test]
    fn test_double_jongseong_split() {
        // ㄱ ㅏ ㅂ ㅅ ㅣ → "갑" 확정 + "시" 조합 (겹종성 분리)
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["r", "k", "q", "t", "l"]);
        assert_eq!(committed, "갑");
        assert_eq!(composing, Some("시".to_string()));
    }

    #[test]
    fn test_double_vowel() {
        // ㄱ ㅗ ㅏ → "과" (겹모음 ㅘ)
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["r", "h", "k"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("과".to_string()));
        assert_eq!(automata.state(), AutomataState::Jungseong2);
    }

    #[test]
    fn test_double_vowel_with_jongseong() {
        // ㄱ ㅗ ㅏ ㄴ → "관"
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["r", "h", "k", "s"]);
        assert_eq!(committed, "");
        assert_eq!(composing, Some("관".to_string()));
    }

    #[test]
    fn test_backspace_from_jongseong() {
        // ㅎ ㅏ ㄴ + backspace → "하"
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        process_keys(&mut automata, &layout, &["g", "k", "s"]);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("하".to_string()));
        assert_eq!(automata.state(), AutomataState::Jungseong);
    }

    #[test]
    fn test_backspace_from_jungseong() {
        // ㅎ ㅏ + backspace → "ㅎ"
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        process_keys(&mut automata, &layout, &["g", "k"]);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("ㅎ".to_string()));
        assert_eq!(automata.state(), AutomataState::Choseong);
    }

    #[test]
    fn test_backspace_from_choseong() {
        // ㅎ + backspace → Empty
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        process_keys(&mut automata, &layout, &["g"]);
        let result = automata.backspace();
        assert_eq!(result.composing, None);
        assert_eq!(automata.state(), AutomataState::Empty);
    }

    #[test]
    fn test_backspace_from_empty() {
        let mut automata = JamoAutomata::new();
        let result = automata.backspace();
        assert!(!result.handled);
    }

    #[test]
    fn test_backspace_from_double_jongseong() {
        // ㄱ ㅏ ㅂ ㅅ + backspace → "갑" (ㅂ+ㅅ=ㅄ 에서 ㅅ 제거)
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        process_keys(&mut automata, &layout, &["r", "k", "q", "t"]);
        assert_eq!(automata.state(), AutomataState::Jongseong2);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("갑".to_string()));
        assert_eq!(automata.state(), AutomataState::Jongseong);
    }

    #[test]
    fn test_backspace_from_double_vowel() {
        // ㄱ ㅗ ㅏ + backspace → "고" (ㅘ에서 ㅏ 제거)
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        process_keys(&mut automata, &layout, &["r", "h", "k"]);
        assert_eq!(automata.state(), AutomataState::Jungseong2);
        let result = automata.backspace();
        assert_eq!(result.composing, Some("고".to_string()));
        assert_eq!(automata.state(), AutomataState::Jungseong);
    }

    #[test]
    fn test_flush() {
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        process_keys(&mut automata, &layout, &["g", "k", "s"]);
        let result = automata.flush();
        assert_eq!(result.committed, Some("한".to_string()));
        assert_eq!(result.composing, None);
        assert_eq!(automata.state(), AutomataState::Empty);
    }

    #[test]
    fn test_jongseong_impossible_ddikkut() {
        // ㄱ ㅏ + ㄸ → "가" 확정 + "ㄸ" 조합 (ㄸ는 종성 불가)
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["r", "k", "E"]);
        assert_eq!(committed, "가");
        assert_eq!(composing, Some("ㄸ".to_string()));
    }

    #[test]
    fn test_vowel_only() {
        // ㅏ 만 입력 → 모음만 표시
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let ch = layout.map_key("k").unwrap();
        let result = automata.process(ch, &layout);
        assert_eq!(result.composing, Some("ㅏ".to_string()));
        assert_eq!(automata.state(), AutomataState::Jungseong);
    }

    #[test]
    fn test_vowel_then_consonant_commits_vowel() {
        // ㅏ + ㄱ → "ㅏ" 확정 + "ㄱ" 조합
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["k", "r"]);
        assert_eq!(committed, "ㅏ");
        assert_eq!(composing, Some("ㄱ".to_string()));
    }

    #[test]
    fn test_backspace_through_double_vowel_with_jongseong() {
        // ㄱ ㅗ ㅏ ㄴ (관) + BS + BS → "과" → "고" (겹모음 복원)
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        process_keys(&mut automata, &layout, &["r", "h", "k", "s"]);
        assert_eq!(automata.state(), AutomataState::Jongseong);

        // BS: 관 → 과
        let result = automata.backspace();
        assert_eq!(result.composing, Some("과".to_string()));
        assert_eq!(automata.state(), AutomataState::Jungseong2);

        // BS: 과 → 고 (겹모음 ㅘ에서 ㅏ 제거)
        let result = automata.backspace();
        assert_eq!(result.composing, Some("고".to_string()));
        assert_eq!(automata.state(), AutomataState::Jungseong);
    }

    #[test]
    fn test_consecutive_consonants() {
        // ㄱ + ㄴ → "ㄱ" 확정 + "ㄴ" 조합
        let layout = make_layout();
        let mut automata = JamoAutomata::new();
        let (committed, composing) =
            process_keys(&mut automata, &layout, &["r", "s"]);
        assert_eq!(committed, "ㄱ");
        assert_eq!(composing, Some("ㄴ".to_string()));
    }
}
