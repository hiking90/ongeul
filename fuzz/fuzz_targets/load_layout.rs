#![no_main]
use libfuzzer_sys::fuzz_target;
use ongeul_automata::HangulEngine;

// 임의의 바이트 시퀀스를 레이아웃 JSON으로 파싱 시도한다.
// JSON5 파서와 레이아웃 검증 로직의 안정성을 검증한다.
// 잘못된 입력에 대해 패닉 없이 에러를 반환해야 한다.
fuzz_target!(|data: &[u8]| {
    let Ok(input) = std::str::from_utf8(data) else {
        return;
    };

    let engine = HangulEngine::new();
    // load_layout이 Result를 반환하므로 에러는 정상 — 패닉만 아니면 된다
    let _ = engine.load_layout(input.to_string());
});
