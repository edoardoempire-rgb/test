use std::env;
use std::ffi::{c_char, c_void, CStr, CString};
use std::fs;
use std::ptr;

use airlift_ffi::{
    al_pairing_result_free, al_pairing_run_host, al_probe_device, al_string_free, ALPairResult,
};
use serde_json::json;

fn string(pointer: *const c_char) -> String {
    if pointer.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(pointer).to_string_lossy().into_owned() }
}

extern "C" fn ready(
    _ctx: *mut c_void,
    service_id: *const c_char,
    port: u16,
    keys: *const *const c_char,
    values: *const *const c_char,
    count: usize,
) {
    let mut txt = serde_json::Map::new();
    if !keys.is_null() && !values.is_null() {
        for index in 0..count {
            let key = unsafe { *keys.add(index) };
            let value = unsafe { *values.add(index) };
            txt.insert(string(key), json!(string(value)));
        }
    }
    println!(
        "GATEWAY_READY {}",
        json!({
            "serviceType": "_remotepairing-pairable-host._tcp",
            "serviceId": string(service_id),
            "port": port,
            "txt": txt
        })
    );
}

extern "C" fn pin(pin: *const c_char, _ctx: *mut c_void) {
    println!("GATEWAY_PIN {}", json!({ "pin": string(pin) }));
}

extern "C" fn log(_ctx: *mut c_void, message: *const c_char) {
    println!("GATEWAY_LOG {}", json!({ "message": string(message) }));
}

fn cstring(value: &str) -> CString {
    CString::new(value).expect("argument contains a NUL byte")
}

fn pair(args: &[String]) -> i32 {
    let output = args.first().map(String::as_str).unwrap_or("airlift_pairing.plist");
    let bind = args.get(1).map(String::as_str).unwrap_or("0.0.0.0");
    let port = args.get(2).and_then(|value| value.parse::<u16>().ok()).unwrap_or(0);
    let alt_irk_path = format!("{output}.altirk");
    let saved_alt_irk = fs::read_to_string(&alt_irk_path).unwrap_or_default();

    let bind = cstring(bind);
    let name = cstring("Wallet Skins Gateway");
    let model = cstring("Mac17,7");
    let output = cstring(output);
    let alt_irk = cstring(saved_alt_irk.trim());
    let mut result = ALPairResult {
        error: ptr::null_mut(),
        device_name: ptr::null_mut(),
        device_model: ptr::null_mut(),
        device_udid: ptr::null_mut(),
        pairing_file_path: ptr::null_mut(),
        host_alt_irk_hex: ptr::null_mut(),
    };

    let rc = unsafe {
        al_pairing_run_host(
            bind.as_ptr(),
            port,
            name.as_ptr(),
            model.as_ptr(),
            output.as_ptr(),
            alt_irk.as_ptr(),
            Some(ready),
            Some(pin),
            ptr::null_mut(),
            &mut result,
        )
    };

    if rc == 0 {
        let issued_alt_irk = string(result.host_alt_irk_hex);
        if !issued_alt_irk.is_empty() {
            if let Err(error) = fs::write(&alt_irk_path, &issued_alt_irk) {
                eprintln!("failed to save gateway identity: {error}");
            }
        }
        println!(
            "PAIRING_COMPLETE {}",
            json!({
                "deviceName": string(result.device_name),
                "deviceModel": string(result.device_model),
                "deviceUdid": string(result.device_udid),
                "pairingFile": string(result.pairing_file_path)
            })
        );
    } else {
        eprintln!("PAIRING_ERROR {}", json!({ "error": string(result.error) }));
    }
    unsafe { al_pairing_result_free(&mut result) };
    rc
}

fn probe(args: &[String]) -> i32 {
    let Some(pairing) = args.first() else {
        eprintln!("usage: airlift-gateway probe PAIRING_FILE DEVICE_IP[:PORT]");
        return 2;
    };
    let Some(endpoint) = args.get(1) else {
        eprintln!("usage: airlift-gateway probe PAIRING_FILE DEVICE_IP[:PORT]");
        return 2;
    };
    env::set_var("AIRLIFT_DEVICE_ENDPOINT", endpoint);
    let pairing = cstring(pairing);
    let mut error: *mut c_char = ptr::null_mut();
    let rc = unsafe {
        al_probe_device(pairing.as_ptr(), Some(log), ptr::null_mut(), &mut error)
    };
    if rc == 0 {
        println!("PROBE_COMPLETE {}", json!({ "endpoint": endpoint }));
    } else {
        eprintln!("PROBE_ERROR {}", json!({ "error": string(error) }));
    }
    if !error.is_null() {
        unsafe { al_string_free(error) };
    }
    rc
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("pair") => pair(&args[1..]),
        Some("probe") => probe(&args[1..]),
        _ => {
            eprintln!("usage: airlift-gateway <pair|probe> [arguments]");
            2
        }
    };
    std::process::exit(code);
}
