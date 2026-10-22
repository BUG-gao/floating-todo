use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager,
};
use tauri_plugin_dialog::DialogExt;

#[cfg(target_os = "windows")]
mod windows_desktop;

#[cfg(desktop)]
#[derive(Default)]
struct ShortcutBindings {
    quick_capture: Option<tauri_plugin_global_shortcut::Shortcut>,
    toggle: Option<tauri_plugin_global_shortcut::Shortcut>,
}

#[cfg(desktop)]
#[derive(Default)]
struct GlobalShortcuts {
    bindings: std::sync::Mutex<ShortcutBindings>,
    recording: std::sync::atomic::AtomicBool,
}

/// 录入期间将已注册的组合回传给输入框，避免触发其原有动作。
#[tauri::command]
fn set_shortcut_recording(app: AppHandle, recording: bool) {
    #[cfg(desktop)]
    app.state::<GlobalShortcuts>()
        .recording
        .store(recording, std::sync::atomic::Ordering::Relaxed);

    #[cfg(not(desktop))]
    let _ = (app, recording);
}

/// 显示或隐藏悬浮窗。
fn toggle_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}

/// 先注册新快捷键，再移除旧快捷键；冲突时保留原设置。
#[tauri::command]
async fn set_global_shortcut(
    app: AppHandle,
    kind: String,
    shortcut: Option<String>,
) -> Result<(), String> {
    #[cfg(desktop)]
    {
        use tauri_plugin_global_shortcut::{GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

        let is_quick_capture = match kind.as_str() {
            "quickCapture" => true,
            "toggle" => false,
            _ => return Err("未知的快捷键类型".to_string()),
        };
        if is_quick_capture && shortcut.is_none() {
            return Err("快速记录快捷键不能为空，可恢复默认组合".to_string());
        }
        let next = match shortcut {
            Some(value) => {
                let parsed: Shortcut = value
                    .parse()
                    .map_err(|_| "无法识别该快捷键，请尝试其他组合".to_string())?;
                if !parsed
                    .mods
                    .intersects(Modifiers::CONTROL | Modifiers::ALT | Modifiers::SUPER)
                {
                    return Err("请至少包含 Ctrl、Alt 或 Cmd / Win 中的一个修饰键".to_string());
                }
                Some(parsed)
            }
            None => None,
        };

        let settings = app.state::<GlobalShortcuts>();
        let mut bindings = settings
            .bindings
            .lock()
            .map_err(|_| "无法更新快捷键，请重启后重试".to_string())?;
        let (current, other) = if is_quick_capture {
            (bindings.quick_capture, bindings.toggle)
        } else {
            (bindings.toggle, bindings.quick_capture)
        };
        if current.as_ref().map(|value| value.id()) == next.as_ref().map(|value| value.id()) {
            return Ok(());
        }
        if let (Some(next_shortcut), Some(other_shortcut)) = (next, other) {
            if next_shortcut.id() == other_shortcut.id() {
                return Err("该组合已用于另一个功能，请选择不同的快捷键".to_string());
            }
        }

        if let Some(next_shortcut) = next {
            app.global_shortcut()
                .on_shortcut(next_shortcut, move |app, shortcut, event| {
                    if event.state == ShortcutState::Pressed {
                        if app
                            .state::<GlobalShortcuts>()
                            .recording
                            .load(std::sync::atomic::Ordering::Relaxed)
                        {
                            let _ = app.emit("shortcut-recorded", shortcut.into_string());
                            return;
                        }
                        if is_quick_capture {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.set_focus();
                                let _ = window.emit("quick-capture", ());
                            }
                        } else {
                            toggle_window(app);
                        }
                    }
                })
                .map_err(|error| format!("快捷键注册失败，可能被系统或其他应用占用，请尝试其他组合。{error}"))?;
        }

        if let Some(previous) = current {
            if let Err(error) = app.global_shortcut().unregister(previous) {
                if let Some(next_shortcut) = next {
                    let _ = app.global_shortcut().unregister(next_shortcut);
                }
                return Err(format!("无法移除旧快捷键，原设置已保留：{error}"));
            }
        }
        if is_quick_capture {
            bindings.quick_capture = next;
        } else {
            bindings.toggle = next;
        }
        Ok(())
    }

    #[cfg(not(desktop))]
    {
        let _ = (app, kind, shortcut);
        Err("当前平台不支持全局快捷键".to_string())
    }
}

/// 导出数据到用户选择的文件。
#[tauri::command]
async fn export_data(app: AppHandle, json: String) -> Result<bool, String> {
    let file = app
        .dialog()
        .file()
        .add_filter("JSON", &["json"])
        .set_file_name("floating-todo-backup.json")
        .blocking_save_file();
    match file {
        Some(p) => {
            let path = p.into_path().map_err(|e| e.to_string())?;
            std::fs::write(path, json).map_err(|e| e.to_string())?;
            Ok(true)
        }
        None => Ok(false),
    }
}

/// 从用户选择的文件导入数据，返回文件内容。
#[tauri::command]
async fn import_data(app: AppHandle) -> Result<Option<String>, String> {
    let file = app
        .dialog()
        .file()
        .add_filter("JSON", &["json"])
        .blocking_pick_file();
    match file {
        Some(p) => {
            let path = p.into_path().map_err(|e| e.to_string())?;
            let content = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
            Ok(Some(content))
        }
        None => Ok(None),
    }
}

/// 将窗口放入 Windows 桌面层，使其在 Win+D 显示桌面后仍然可见。
#[tauri::command]
fn set_desktop_mode(app: AppHandle, enabled: bool) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        let window = app
            .get_webview_window("main")
            .ok_or_else(|| "main window not found".to_string())?;
        let hwnd = window.hwnd().map_err(|error| error.to_string())?;
        windows_desktop::set_desktop_mode(hwnd, enabled)
    }

    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app, enabled);
        Ok(())
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_dialog::init());

    #[cfg(desktop)]
    {
        builder = builder
            .manage(GlobalShortcuts::default())
            .plugin(tauri_plugin_global_shortcut::Builder::new().build())
            .plugin(tauri_plugin_autostart::init(
                tauri_plugin_autostart::MacosLauncher::LaunchAgent,
                Some(vec![]),
            ));
    }

    builder
        .invoke_handler(tauri::generate_handler![
            export_data,
            import_data,
            set_desktop_mode,
            set_global_shortcut,
            set_shortcut_recording
        ])
        .setup(|app| {
            // macOS：作为状态栏小组件运行，不占用程序坞。
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            if let Some(win) = app.get_webview_window("main") {
                let _ = win.show();
                let _ = win.set_focus();
            }

            // 快捷键由前端读取本地设置后注册，兼容旧数据的默认快速记录组合。

            let toggle_item =
                MenuItem::with_id(app, "toggle", "显示/隐藏小组件", true, None::<&str>)?;
            #[cfg(target_os = "windows")]
            let desktop_item =
                MenuItem::with_id(app, "desktop", "切换固定在桌面", true, None::<&str>)?;
            let passthrough_item =
                MenuItem::with_id(app, "passthrough", "切换鼠标穿透", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
            #[cfg(target_os = "windows")]
            let menu = Menu::with_items(
                app,
                &[&toggle_item, &desktop_item, &passthrough_item, &quit_item],
            )?;
            #[cfg(not(target_os = "windows"))]
            let menu = Menu::with_items(app, &[&toggle_item, &passthrough_item, &quit_item])?;

            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("悬浮待办")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "toggle" => toggle_window(app),
                    "passthrough" => {
                        if let Some(win) = app.get_webview_window("main") {
                            let _ = win.show();
                            let _ = win.emit("toggle-passthrough", ());
                        }
                    }
                    "desktop" => {
                        if let Some(win) = app.get_webview_window("main") {
                            let _ = win.show();
                            let _ = win.emit("toggle-desktop-mode", ());
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_window(tray.app_handle());
                    }
                })
                .build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
