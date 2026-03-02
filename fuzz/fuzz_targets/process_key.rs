#![no_main]
use libfuzzer_sys::fuzz_target;
use ongeul_automata::{HangulEngine, InputMode};

// 임의의 바이트 시퀀스를 UTF-8 문자열로 변환한 뒤,
// 각 문자를 키 레이블로 HangulEngine에 전달한다.
// proptest의 `no_panic_on_arbitrary_keys`와 유사하나,
// 퍼저가 코드 커버리지를 기반으로 입력을 진화시키므로
// 더 깊은 경로를 탐색할 수 있다.
fuzz_target!(|data: &[u8]| {
    let Ok(input) = std::str::from_utf8(data) else {
        return;
    };

    let engine = HangulEngine::new();
    let _ = engine.load_layout(
        include_str!("../../ongeul-automata/layouts/2-standard.json5").to_string(),
    );
    engine.set_mode(InputMode::Korean);

    for ch in input.chars() {
        let _ = engine.process_key(ch.to_string());
    }
    let _ = engine.flush();
});
