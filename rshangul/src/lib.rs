pub mod automata;
pub mod engine;
pub mod layout;
pub mod unicode;

use std::sync::Mutex;

use engine::EngineState;

uniffi::setup_scaffolding!();

/// 키 처리 결과 (UniFFI → Swift 전달용)
#[derive(uniffi::Record, Debug, Clone)]
pub struct ProcessResult {
    /// 확정된 텍스트
    pub committed: Option<String>,
    /// 조합 중인 텍스트
    pub composing: Option<String>,
    /// 키가 처리되었는지 (false면 시스템에 위임)
    pub handled: bool,
}

/// 입력 모드 (UniFFI enum)
#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputMode {
    English,
    Korean,
}

impl From<engine::InputMode> for InputMode {
    fn from(mode: engine::InputMode) -> Self {
        match mode {
            engine::InputMode::English => InputMode::English,
            engine::InputMode::Korean => InputMode::Korean,
        }
    }
}

impl From<InputMode> for engine::InputMode {
    fn from(mode: InputMode) -> Self {
        match mode {
            InputMode::English => engine::InputMode::English,
            InputMode::Korean => engine::InputMode::Korean,
        }
    }
}

/// 한글 입력 엔진 (UniFFI object, thread-safe)
#[derive(uniffi::Object)]
pub struct HangulEngine {
    state: Mutex<EngineState>,
}

impl Default for HangulEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[uniffi::export]
impl HangulEngine {
    /// 새 엔진을 생성한다. (English 모드, 레이아웃 미로드)
    #[uniffi::constructor]
    pub fn new() -> Self {
        HangulEngine {
            state: Mutex::new(EngineState::new()),
        }
    }

    /// JSON5 문자열로 자판 레이아웃을 로드한다.
    pub fn load_layout(&self, json: String) -> Result<(), String> {
        let mut state = self.state.lock().unwrap();
        state.load_layout(&json)
    }

    /// 입력 모드를 설정한다.
    pub fn set_mode(&self, mode: InputMode) {
        let mut state = self.state.lock().unwrap();
        if state.mode == engine::InputMode::Korean && mode == InputMode::English {
            // 한→영 전환 시 현재 조합 확정
            let _ = state.flush();
        }
        state.mode = mode.into();
    }

    /// 현재 입력 모드를 반환한다.
    pub fn get_mode(&self) -> InputMode {
        let state = self.state.lock().unwrap();
        state.mode.into()
    }

    /// 입력 모드를 토글한다.
    pub fn toggle_mode(&self) -> InputMode {
        let mut state = self.state.lock().unwrap();
        if state.mode == engine::InputMode::Korean {
            let _ = state.flush();
            state.mode = engine::InputMode::English;
        } else {
            state.mode = engine::InputMode::Korean;
        }
        state.mode.into()
    }

    /// 키 레이블을 처리한다. (예: "q", "Q", "k")
    pub fn process_key(&self, key: String) -> ProcessResult {
        let mut state = self.state.lock().unwrap();
        let result = state.process_key(&key);
        ProcessResult {
            committed: result.committed,
            composing: result.composing,
            handled: result.handled,
        }
    }

    /// 백스페이스 처리 (오토마타 한 단계 되돌림)
    pub fn backspace(&self) -> ProcessResult {
        let mut state = self.state.lock().unwrap();
        let result = state.backspace();
        ProcessResult {
            committed: result.committed,
            composing: result.composing,
            handled: result.handled,
        }
    }

    /// 현재 조합을 확정한다.
    pub fn flush(&self) -> ProcessResult {
        let mut state = self.state.lock().unwrap();
        let result = state.flush();
        ProcessResult {
            committed: result.committed,
            composing: result.composing,
            handled: result.handled,
        }
    }

    /// 현재 조합을 폐기한다.
    pub fn reset(&self) {
        let mut state = self.state.lock().unwrap();
        state.reset();
    }
}
