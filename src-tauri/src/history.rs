use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::DialogExt;

const HISTORY_FILE_NAME: &str = "floating-todo-history.json";
const CONFIG_FILE_NAME: &str = "history-config.json";

#[derive(Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct HistoryDocument {
    #[serde(default = "default_schema_version")]
    schema_version: u32,
    #[serde(default)]
    updated_at: u64,
    #[serde(default)]
    records: Vec<Value>,
}

#[derive(Debug, Deserialize, Serialize)]
struct HistoryConfig {
    directory: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryStatus {
    directory: String,
    file_path: String,
    record_count: usize,
}

fn default_schema_version() -> u32 {
    1
}

fn unix_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn config_path(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_config_dir()
        .map(|path| path.join(CONFIG_FILE_NAME))
        .map_err(|error| error.to_string())
}

fn default_history_directory(app: &AppHandle) -> Result<PathBuf, String> {
    match app.path().document_dir() {
        Ok(path) => Ok(path.join("悬浮待办")),
        Err(_) => app
            .path()
            .app_data_dir()
            .map(|path| path.join("history"))
            .map_err(|error| error.to_string()),
    }
}

fn configured_directory(app: &AppHandle) -> Result<PathBuf, String> {
    let path = config_path(app)?;
    if path.exists() {
        let content = fs::read_to_string(&path).map_err(|error| error.to_string())?;
        let config: HistoryConfig =
            serde_json::from_str(&content).map_err(|error| error.to_string())?;
        if !config.directory.trim().is_empty() {
            return Ok(PathBuf::from(config.directory));
        }
    }
    default_history_directory(app)
}

fn save_config(app: &AppHandle, directory: &Path) -> Result<(), String> {
    let path = config_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let config = HistoryConfig {
        directory: directory.to_string_lossy().into_owned(),
    };
    let json = serde_json::to_string_pretty(&config).map_err(|error| error.to_string())?;
    fs::write(path, json).map_err(|error| error.to_string())
}

fn history_path(directory: &Path) -> PathBuf {
    directory.join(HISTORY_FILE_NAME)
}

fn load_document(path: &Path) -> Result<HistoryDocument, String> {
    if !path.exists() {
        return Ok(HistoryDocument {
            schema_version: default_schema_version(),
            updated_at: unix_millis(),
            records: Vec::new(),
        });
    }
    let content = fs::read_to_string(path).map_err(|error| error.to_string())?;
    serde_json::from_str(&content).map_err(|error| {
        format!(
            "历史文件格式损坏，已停止写入以保护原文件：{} ({error})",
            path.display()
        )
    })
}

fn record_id(record: &Value) -> Option<&str> {
    record.get("recordId").and_then(Value::as_str)
}

fn record_sort_key(record: &Value) -> String {
    let task_date = record
        .get("taskDate")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let archived_at = record
        .get("archivedAt")
        .and_then(Value::as_u64)
        .unwrap_or_default();
    format!("{task_date}:{archived_at:020}")
}

fn merge_records(target: &mut HistoryDocument, incoming: Vec<Value>) {
    let mut positions: HashMap<String, usize> = target
        .records
        .iter()
        .enumerate()
        .filter_map(|(index, record)| record_id(record).map(|id| (id.to_string(), index)))
        .collect();

    for record in incoming {
        let Some(id) = record_id(&record).map(str::to_string) else {
            continue;
        };
        if let Some(index) = positions.get(&id).copied() {
            target.records[index] = record;
        } else {
            positions.insert(id, target.records.len());
            target.records.push(record);
        }
    }
}

fn write_document(path: &Path, document: &mut HistoryDocument) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    document.schema_version = default_schema_version();
    document.updated_at = unix_millis();
    document
        .records
        .sort_by_key(|record| std::cmp::Reverse(record_sort_key(record)));
    let json = serde_json::to_string_pretty(document).map_err(|error| error.to_string())?;

    let temporary = path.with_extension("json.tmp");
    let backup = path.with_extension("json.bak");
    fs::write(&temporary, json).map_err(|error| error.to_string())?;
    if path.exists() {
        fs::copy(path, &backup).map_err(|error| error.to_string())?;
    }
    if let Err(error) = fs::rename(&temporary, path) {
        if path.exists() {
            fs::remove_file(path).map_err(|remove_error| remove_error.to_string())?;
            fs::rename(&temporary, path).map_err(|rename_error| rename_error.to_string())?;
        } else {
            return Err(error.to_string());
        }
    }
    Ok(())
}

fn ensure_document(app: &AppHandle) -> Result<(PathBuf, HistoryDocument), String> {
    let directory = configured_directory(app)?;
    let path = history_path(&directory);
    let mut document = load_document(&path)?;
    if !path.exists() {
        write_document(&path, &mut document)?;
    }
    Ok((path, document))
}

fn status_for(path: &Path, document: &HistoryDocument) -> HistoryStatus {
    HistoryStatus {
        directory: path.parent().unwrap_or(path).to_string_lossy().into_owned(),
        file_path: path.to_string_lossy().into_owned(),
        record_count: document.records.len(),
    }
}

#[tauri::command]
pub fn get_history_status(app: AppHandle) -> Result<HistoryStatus, String> {
    let (path, document) = ensure_document(&app)?;
    Ok(status_for(&path, &document))
}

#[tauri::command]
pub fn read_history(app: AppHandle) -> Result<String, String> {
    let (_, document) = ensure_document(&app)?;
    serde_json::to_string_pretty(&document).map_err(|error| error.to_string())
}

#[tauri::command]
pub fn update_history(
    app: AppHandle,
    upserts: Vec<Value>,
    remove_ids: Vec<String>,
) -> Result<HistoryStatus, String> {
    let (path, mut document) = ensure_document(&app)?;
    if !remove_ids.is_empty() {
        let removals: HashSet<&str> = remove_ids.iter().map(String::as_str).collect();
        document
            .records
            .retain(|record| record_id(record).is_none_or(|id| !removals.contains(id)));
    }
    merge_records(&mut document, upserts);
    write_document(&path, &mut document)?;
    Ok(status_for(&path, &document))
}

#[tauri::command]
pub fn choose_history_directory(app: AppHandle) -> Result<Option<HistoryStatus>, String> {
    let selected = app.dialog().file().blocking_pick_folder();
    let Some(selected) = selected else {
        return Ok(None);
    };
    let new_directory = selected.into_path().map_err(|error| error.to_string())?;
    fs::create_dir_all(&new_directory).map_err(|error| error.to_string())?;

    let (old_path, old_document) = ensure_document(&app)?;
    let new_path = history_path(&new_directory);
    let mut new_document = load_document(&new_path)?;
    merge_records(&mut new_document, old_document.records);
    write_document(&new_path, &mut new_document)?;
    save_config(&app, &new_directory)?;

    // 切换路径采用复制合并，旧文件刻意保留，避免误删用户历史。
    let _ = old_path;
    Ok(Some(status_for(&new_path, &new_document)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn test_directory(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "floating-todo-history-{name}-{}-{}",
            std::process::id(),
            unix_millis()
        ))
    }

    #[test]
    fn upserts_records_by_stable_record_id() {
        let mut document = HistoryDocument::default();
        merge_records(
            &mut document,
            vec![json!({
                "recordId": "normal:1:2026-11-23",
                "taskDate": "2026-11-23",
                "title": "初始标题",
                "archivedAt": 1
            })],
        );
        merge_records(
            &mut document,
            vec![json!({
                "recordId": "normal:1:2026-11-23",
                "taskDate": "2026-11-23",
                "title": "更新后的标题",
                "archivedAt": 2
            })],
        );

        assert_eq!(document.records.len(), 1);
        assert_eq!(document.records[0]["title"], "更新后的标题");
    }

    #[test]
    fn writes_readable_json_and_keeps_previous_backup() {
        let directory = test_directory("write");
        let path = history_path(&directory);
        let mut document = HistoryDocument::default();
        merge_records(
            &mut document,
            vec![json!({
                "recordId": "normal:2:2026-11-23",
                "taskDate": "2026-11-23",
                "title": "验证落盘",
                "status": "completed",
                "archivedAt": 3
            })],
        );

        write_document(&path, &mut document).expect("first history write should succeed");
        document.records[0]["title"] = json!("第二次写入");
        write_document(&path, &mut document).expect("second history write should succeed");

        let current = load_document(&path).expect("current history should be readable");
        let backup = load_document(&path.with_extension("json.bak"))
            .expect("backup history should be readable");
        assert_eq!(current.records[0]["title"], "第二次写入");
        assert_eq!(backup.records[0]["title"], "验证落盘");

        fs::remove_dir_all(&directory).expect("test directory should be removable");
    }
}
