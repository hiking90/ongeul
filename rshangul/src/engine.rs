/// 엔진 내부 상태: 입력 모드, 레이아웃, 오토마타를 관리한다.
use crate::automata::{self, Automata, AutomataResult};
use crate::layout::KeyboardLayout;

/// 입력 모드
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputMode {
    English,
    Korean,
}

/// 엔진 내부 가변 상태
pub struct EngineState {
    pub mode: InputMode,
    layout: Option<KeyboardLayout>,
    automata: Option<Box<dyn Automata + Send>>,
}

impl Default for EngineState {
    fn default() -> Self {
        Self::new()
    }
}

impl EngineState {
    pub fn new() -> Self {
        EngineState {
            mode: InputMode::English,
            layout: None,
            automata: None,
        }
    }

    /// JSON5 문자열로 레이아웃을 로드하고 오토마타를 생성한다.
    pub fn load_layout(&mut self, json: &str) -> Result<(), String> {
        let layout = KeyboardLayout::from_json(json)?;
        let auto = automata::create_automata(&layout);
        self.layout = Some(layout);
        self.automata = Some(auto);
        Ok(())
    }

    /// 키 레이블을 처리한다.
    pub fn process_key(&mut self, key: &str) -> AutomataResult {
        // 영문 모드: 키를 그대로 committed로 반환 (단독 입력 소스 전략)
        if self.mode == InputMode::English {
            return AutomataResult::handled(Some(key.to_string()), None);
        }

        let (layout, automata) = match (&self.layout, &mut self.automata) {
            (Some(l), Some(a)) => (l, a),
            _ => return AutomataResult::not_handled(),
        };

        let ch = match layout.map_key(key) {
            Some(ch) => ch,
            None => {
                // 레이아웃에 없는 키 → 현재 조합 확정 후 패스스루
                let mut result = automata.flush();
                result.handled = false;
                return result;
            }
        };

        automata.process(ch, layout)
    }

    /// 백스페이스 처리
    pub fn backspace(&mut self) -> AutomataResult {
        if self.mode == InputMode::English {
            return AutomataResult::not_handled();
        }
        match &mut self.automata {
            Some(a) => a.backspace(),
            None => AutomataResult::not_handled(),
        }
    }

    /// 현재 조합을 확정한다.
    pub fn flush(&mut self) -> AutomataResult {
        match &mut self.automata {
            Some(a) => a.flush(),
            None => AutomataResult::handled(None, None),
        }
    }

    /// 현재 조합을 폐기한다.
    pub fn reset(&mut self) {
        if let Some(a) = &mut self.automata {
            // flush하고 결과를 버린다
            let _ = a.flush();
        }
    }

    /// 현재 조합 중인 텍스트
    pub fn composing_text(&self) -> Option<String> {
        self.automata.as_ref().and_then(|a| a.composing_text())
    }
}
