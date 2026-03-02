#![no_main]
use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;
use ongeul_automata::{HangulEngine, InputMode};

/// 엔진에 대해 수행할 수 있는 모든 연산을 표현한다.
/// `Arbitrary` derive로 퍼저가 구조화된 연산 시퀀스를 생성한다.
#[derive(Arbitrary, Debug)]
enum Op {
    /// 키 레이블 입력 (임의 문자열)
    ProcessKey(String),
    /// 백스페이스
    Backspace,
    /// 모드 토글 (한/영)
    ToggleMode,
    /// 현재 조합 확정
    Flush,
    /// 현재 조합 폐기
    Reset,
    /// 모드 직접 설정
    SetMode(bool),
    /// 레이아웃 전환 (0=2벌식, 1=3벌식390, 2=3벌식최종)
    SwitchLayout(u8),
}

static LAYOUTS: &[&str] = &[
    include_str!("../../ongeul-automata/layouts/2-standard.json5"),
    include_str!("../../ongeul-automata/layouts/3-390.json5"),
    include_str!("../../ongeul-automata/layouts/3-final.json5"),
];

// 임의의 연산 시퀀스를 엔진에 적용한다.
// process_key + backspace + mode toggle + flush + reset + layout switch가
// 어떤 순서로 호출되어도 패닉이 발생하지 않아야 한다.
fuzz_target!(|ops: Vec<Op>| {
    let engine = HangulEngine::new();
    let _ = engine.load_layout(LAYOUTS[0].to_string());
    engine.set_mode(InputMode::Korean);

    for op in &ops {
        match op {
            Op::ProcessKey(key) => {
                let _ = engine.process_key(key.clone());
            }
            Op::Backspace => {
                let _ = engine.backspace();
            }
            Op::ToggleMode => {
                let _ = engine.toggle_mode();
            }
            Op::Flush => {
                let _ = engine.flush();
            }
            Op::Reset => {
                engine.reset();
            }
            Op::SetMode(korean) => {
                engine.set_mode(if *korean {
                    InputMode::Korean
                } else {
                    InputMode::English
                });
            }
            Op::SwitchLayout(idx) => {
                let layout = LAYOUTS[(*idx as usize) % LAYOUTS.len()];
                let _ = engine.load_layout(layout.to_string());
            }
        }
    }
});
