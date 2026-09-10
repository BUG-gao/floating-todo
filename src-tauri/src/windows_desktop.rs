//! Windows desktop-layer integration.
//!
//! Explorer exposes the wallpaper/desktop surface through Progman and WorkerW
//! windows. Parenting the widget there makes it survive "Show desktop" without
//! turning it into a global topmost overlay.

use std::sync::{Mutex, OnceLock};

use windows::core::{w, BOOL};
use windows::Win32::Foundation::{HWND, LPARAM, POINT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::ScreenToClient;
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, FindWindowExW, FindWindowW, GetParent, GetWindowLongPtrW, GetWindowRect,
    SendMessageTimeoutW, SetParent, SetWindowLongPtrW, SetWindowPos, GWL_STYLE, SMTO_NORMAL,
    SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOSIZE, SWP_NOZORDER, WS_CHILD, WS_POPUP,
};

const DESKTOP_HOST_MESSAGE: u32 = 0x052c;

// Keep the original borderless-window style so disabling desktop mode restores it exactly.
static ORIGINAL_STYLE: OnceLock<Mutex<Option<isize>>> = OnceLock::new();

fn original_style() -> &'static Mutex<Option<isize>> {
    ORIGINAL_STYLE.get_or_init(|| Mutex::new(None))
}

unsafe extern "system" fn find_desktop_worker(hwnd: HWND, param: LPARAM) -> BOOL {
    let worker = &mut *(param.0 as *mut HWND);

    if FindWindowExW(Some(hwnd), None, w!("SHELLDLL_DefView"), None).is_ok() {
        if let Ok(candidate) = FindWindowExW(None, Some(hwnd), w!("WorkerW"), None) {
            *worker = candidate;
        }
        return BOOL(0);
    }

    BOOL(1)
}

fn desktop_host() -> Option<HWND> {
    let progman = unsafe { FindWindowW(w!("Progman"), None).ok()? };

    // Ask Explorer to create the WorkerW desktop layer if it is not present.
    unsafe {
        let _ = SendMessageTimeoutW(
            progman,
            DESKTOP_HOST_MESSAGE,
            WPARAM(0),
            LPARAM(0),
            SMTO_NORMAL,
            1000,
            None,
        );
    }

    let mut worker = HWND::default();
    unsafe {
        let _ = EnumWindows(
            Some(find_desktop_worker),
            LPARAM(&mut worker as *mut HWND as isize),
        );
    }

    if worker.is_invalid() {
        Some(progman)
    } else {
        Some(worker)
    }
}

fn desktop_child_style(style: isize) -> isize {
    ((style as u32 & !WS_POPUP.0) | WS_CHILD.0) as isize
}

fn window_rect(hwnd: HWND) -> Result<RECT, String> {
    let mut rect = RECT::default();
    unsafe { GetWindowRect(hwnd, &mut rect) }.map_err(|error| error.to_string())?;
    Ok(rect)
}

fn position_and_refresh(hwnd: HWND, position: POINT) -> Result<(), String> {
    unsafe {
        SetWindowPos(
            hwnd,
            None,
            position.x,
            position.y,
            0,
            0,
            SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
        )
    }
    .map_err(|error| error.to_string())
}

fn restore_top_level(hwnd: HWND, style: isize, position: POINT) -> Result<(), String> {
    unsafe {
        let _ = SetParent(hwnd, None);
        SetWindowLongPtrW(hwnd, GWL_STYLE, style);
    }
    position_and_refresh(hwnd, position)
}

pub fn set_desktop_mode(hwnd: HWND, enabled: bool) -> Result<(), String> {
    let mut saved_style = original_style()
        .lock()
        .map_err(|_| "desktop window style lock is poisoned".to_string())?;

    if enabled {
        let screen_rect = window_rect(hwnd)?;
        let host = desktop_host().ok_or_else(|| "Windows desktop host not found".to_string())?;
        let screen_position = POINT {
            x: screen_rect.left,
            y: screen_rect.top,
        };
        let mut desktop_position = screen_position;
        if !unsafe { ScreenToClient(host, &mut desktop_position) }.as_bool() {
            return Err(windows::core::Error::from_win32().to_string());
        }

        let current_style = unsafe { GetWindowLongPtrW(hwnd, GWL_STYLE) };
        let original_style = saved_style.unwrap_or(current_style);
        *saved_style = Some(original_style);
        let child_style = desktop_child_style(current_style);
        unsafe {
            SetWindowLongPtrW(hwnd, GWL_STYLE, child_style);
            // For a top-level window SetParent returns a null previous parent.
            // The Windows API call still succeeds, so its wrapper error is ignored.
            let _ = SetParent(hwnd, Some(host));
        }

        let actual_parent = match unsafe { GetParent(hwnd) } {
            Ok(parent) => parent,
            Err(error) => {
                let _ = restore_top_level(hwnd, original_style, screen_position);
                *saved_style = None;
                return Err(error.to_string());
            }
        };
        if actual_parent != host {
            let _ = restore_top_level(hwnd, original_style, screen_position);
            *saved_style = None;
            return Err("failed to attach window to the Windows desktop host".to_string());
        }

        if let Err(error) = position_and_refresh(hwnd, desktop_position) {
            let _ = restore_top_level(hwnd, original_style, screen_position);
            *saved_style = None;
            return Err(error);
        }

        Ok(())
    } else if let Some(style) = *saved_style {
        let screen_rect = window_rect(hwnd)?;
        unsafe {
            let _ = SetParent(hwnd, None);
        }
        if unsafe { GetParent(hwnd) }.is_ok() {
            return Err("failed to detach window from the Windows desktop host".to_string());
        }
        unsafe { SetWindowLongPtrW(hwnd, GWL_STYLE, style) };
        position_and_refresh(
            hwnd,
            POINT {
                x: screen_rect.left,
                y: screen_rect.top,
            },
        )?;
        *saved_style = None;
        Ok(())
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_style_replaces_popup_with_child() {
        let original = WS_POPUP.0 as isize | 0x0080_0000;
        let result = desktop_child_style(original);

        assert_eq!(result & WS_POPUP.0 as isize, 0);
        assert_ne!(result & WS_CHILD.0 as isize, 0);
        assert_ne!(result & 0x0080_0000, 0);
    }
}
