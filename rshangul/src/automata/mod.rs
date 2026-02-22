/// 오토마타 트레잇, 상태, 조합 버퍼, 팩토리
pub mod jamo;
pub mod jaso;

use crate::layout::KeyboardLayout;
use crate::layout::schema::LayoutType;
use crate::unicode;

/// 오토마타 상태 (두벌식 6상태)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AutomataState {
    /// 초기 상태 — 조합 없음
    Empty,
    /// 초성 입력됨
    Choseong,
    /// 중성 입력됨 (초성+중성 또는 중성만)
    Jungseong,
    /// 겹모음 입력됨
    Jungseong2,
    /// 종성 입력됨
    Jongseong,
    /// 겹종성 입력됨
    Jongseong2,
}

/// 조합 버퍼 — 현재 조합 중인 자모 정보
#[derive(Debug, Clone)]
pub struct ComposeBuffer {
    /// 초성 인덱스 (L)
    pub choseong: Option<u32>,
    /// 중성 인덱스 (V)
    pub jungseong: Option<u32>,
    /// 종성 인덱스 (T)
    pub jongseong: Option<u32>,
    /// 현재 상태
    pub state: AutomataState,
}

impl Default for ComposeBuffer {
    fn default() -> Self {
        Self::new()
    }
}

impl ComposeBuffer {
    pub fn new() -> Self {
        ComposeBuffer {
            choseong: None,
            jungseong: None,
            jongseong: None,
            state: AutomataState::Empty,
        }
    }

    /// 버퍼를 초기화한다.
    pub fn reset(&mut self) {
        self.choseong = None;
        self.jungseong = None;
        self.jongseong = None;
        self.state = AutomataState::Empty;
    }

    /// 현재 버퍼로 합성된 문자열을 반환한다.
    pub fn to_string(&self) -> Option<String> {
        match (self.choseong, self.jungseong) {
            (Some(l), Some(v)) => {
                let t = self.jongseong.unwrap_or(0);
                unicode::compose_syllable(l, v, t).map(|ch| ch.to_string())
            }
            (Some(l), None) => {
                // 초성만 — 호환 자모로 표시
                unicode::choseong_to_compat(l).map(|ch| ch.to_string())
            }
            (None, Some(v)) => {
                // 중성만 — 호환 자모로 표시
                unicode::jungseong_to_compat(v).map(|ch| ch.to_string())
            }
            (None, None) => None,
        }
    }
}

/// 오토마타 처리 결과
#[derive(Debug, Clone)]
pub struct AutomataResult {
    /// 확정된 텍스트 (이전 조합이 완성된 경우)
    pub committed: Option<String>,
    /// 현재 조합 중인 텍스트
    pub composing: Option<String>,
    /// 키가 처리되었는지 (false면 시스템에 위임)
    pub handled: bool,
}

impl AutomataResult {
    pub fn handled(committed: Option<String>, composing: Option<String>) -> Self {
        AutomataResult {
            committed,
            composing,
            handled: true,
        }
    }

    pub fn not_handled() -> Self {
        AutomataResult {
            committed: None,
            composing: None,
            handled: false,
        }
    }
}

/// 오토마타 트레잇 — 두벌식/세벌식 공통 인터페이스
pub trait Automata {
    /// 자모 문자 하나를 처리한다.
    fn process(&mut self, ch: char, layout: &KeyboardLayout) -> AutomataResult;
    /// 백스페이스 처리 (한 단계 되돌림)
    fn backspace(&mut self) -> AutomataResult;
    /// 현재 조합을 확정하고 리셋한다.
    fn flush(&mut self) -> AutomataResult;
    /// 현재 조합 중인 텍스트를 반환한다.
    fn composing_text(&self) -> Option<String>;
    /// 현재 오토마타 상태를 반환한다.
    fn state(&self) -> AutomataState;
}

/// 레이아웃 타입에 따라 적절한 오토마타를 생성한다.
pub fn create_automata(layout: &KeyboardLayout) -> Box<dyn Automata + Send> {
    match layout.layout_type {
        LayoutType::Jamo => Box::new(jamo::JamoAutomata::new()),
        LayoutType::Jaso => Box::new(jaso::JasoAutomata::new()),
    }
}
