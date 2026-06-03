pub mod automata;
pub mod engine;
pub mod layout;
pub mod unicode;

use std::sync::{Mutex, MutexGuard};

use automata::AutomataResult;
use engine::EngineState;

uniffi::setup_scaffolding!();

/// 예상치 못한 상황 발생 시 경고 로그를 출력한다.
/// 단일 지점으로 격리하여 향후 `log` 크레이트나 macOS unified logging으로 교체 가능.
pub(crate) fn warn_unexpected(context: &str, detail: impl std::fmt::Debug) {
    eprintln!("[ongeul] {context}: {detail:?}");
}

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

impl From<AutomataResult> for ProcessResult {
    fn from(r: AutomataResult) -> Self {
        ProcessResult {
            committed: r.committed,
            composing: r.composing,
            handled: r.handled,
        }
    }
}

/// 엔진 에러 (UniFFI → Swift 전달용)
#[derive(uniffi::Error, Debug, thiserror::Error)]
pub enum EngineError {
    #[error("{message}")]
    LayoutError { message: String },
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

impl HangulEngine {
    /// Mutex lock을 안전하게 획득한다.
    /// Poison 발생 시 상태를 리셋하고 복구한다.
    fn lock_state(&self) -> MutexGuard<'_, EngineState> {
        self.state.lock().unwrap_or_else(|e| {
            warn_unexpected("Mutex poisoned", "recovering");
            let mut guard = e.into_inner();
            guard.reset();
            guard
        })
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
    pub fn load_layout(&self, json: String) -> Result<(), EngineError> {
        let mut state = self.lock_state();
        state
            .load_layout(&json)
            .map_err(|e| EngineError::LayoutError { message: e })
    }

    /// 입력 모드를 설정한다.
    ///
    /// # 호출 계약 (중요)
    /// 한글 → 영문 전환 시 조합 중이던 글자를 내부적으로 flush하지만 그 **확정 텍스트(committed)는
    /// 폐기**한다. 따라서 조합 중인 텍스트가 있을 수 있는 상태에서 모드를 바꿀 때는 **반드시
    /// 호출자가 먼저 [`flush`](Self::flush)(또는 결과를 반환하는 [`toggle_mode`](Self::toggle_mode))를
    /// 호출해 committed를 client에 적용**해야 한다. 그렇지 않으면 확정 텍스트가 소리 없이 사라진다.
    ///
    /// 내부 flush는 "호출자가 flush를 누락했더라도 다음 한글 입력에 잔여 조합이 되살아나지 않도록"
    /// 하는 방어적 폐기일 뿐, 데이터 전달 경로가 아니다. 현재 Swift `InputStateCoordinator`의
    /// 모든 한→영 경로는 이 계약을 지켜 set_mode 이전에 flush 결과를 적용한다.
    pub fn set_mode(&self, mode: InputMode) {
        let mut state = self.lock_state();
        if state.mode == engine::InputMode::Korean && mode == InputMode::English {
            // 한→영 전환 시 잔여 조합을 폐기한다 (committed는 호출자가 별도 flush로 이미 적용했어야 함 — 위 계약 참조).
            let _ = state.flush();
        }
        state.mode = mode.into();
    }

    /// 현재 입력 모드를 반환한다.
    pub fn get_mode(&self) -> InputMode {
        let state = self.lock_state();
        state.mode.into()
    }

    /// 입력 모드를 토글한다. flush 결과를 포함한 ProcessResult를 반환한다.
    pub fn toggle_mode(&self) -> ProcessResult {
        let mut state = self.lock_state();
        if state.mode == engine::InputMode::Korean {
            let result = state.flush();
            state.mode = engine::InputMode::English;
            result.into()
        } else {
            state.mode = engine::InputMode::Korean;
            ProcessResult {
                committed: None,
                composing: None,
                handled: true,
            }
        }
    }

    /// 키 레이블을 처리한다. (예: "q", "Q", "k")
    pub fn process_key(&self, key: String) -> ProcessResult {
        let mut state = self.lock_state();
        state.process_key(&key).into()
    }

    /// 백스페이스 처리 (오토마타 한 단계 되돌림)
    pub fn backspace(&self) -> ProcessResult {
        let mut state = self.lock_state();
        state.backspace().into()
    }

    /// 현재 조합을 확정한다.
    pub fn flush(&self) -> ProcessResult {
        let mut state = self.lock_state();
        state.flush().into()
    }

    /// 현재 조합을 폐기한다.
    pub fn reset(&self) {
        let mut state = self.lock_state();
        state.reset();
    }
}
