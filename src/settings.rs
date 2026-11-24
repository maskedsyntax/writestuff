use crate::document::Snapshot;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum Appearance {
    #[default]
    System,
    Light,
    Dark,
}
impl std::fmt::Display for Appearance {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum Typeface {
    #[default]
    Monospace,
    Sans,
    Serif,
}
impl std::fmt::Display for Typeface {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub appearance: Appearance,
    pub font: Typeface,
    pub size: f32,
    pub line_height: f32,
    pub wrap: bool,
    pub status: bool,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            appearance: Appearance::System,
            font: Typeface::Monospace,
            size: 16.0,
            line_height: 1.6,
            wrap: true,
            status: true,
        }
    }
}
#[derive(Default, Serialize, Deserialize)]
pub struct Session {
    pub settings: Settings,
    pub documents: Vec<Snapshot>,
    pub active: Option<u64>,
}
pub fn path() -> Option<PathBuf> {
    if let Some(directory) = std::env::var_os("WRITESTUFF_CONFIG_DIR") {
        return Some(PathBuf::from(directory).join("session.json"));
    }
    directories::ProjectDirs::from("", "", "writestuff")
        .map(|d| d.config_dir().join("session.json"))
}
pub fn load() -> Result<(Session, Option<String>), String> {
    let path = path().ok_or("No configuration directory is available")?;
    load_at(&path)
}
fn load_at(path: &std::path::Path) -> Result<(Session, Option<String>), String> {
    match std::fs::read(path) {
        Ok(bytes) => match serde_json::from_slice(&bytes) {
            Ok(session) => Ok((session, None)),
            Err(error) => {
                let backup = std::fs::read(path.with_extension("json.bak"))
                    .ok()
                    .and_then(|bytes| serde_json::from_slice(&bytes).ok());
                if let Some(session) = backup {
                    Ok((
                        session,
                        Some(format!(
                            "Recovery snapshot was damaged ({error}); restored the previous backup."
                        )),
                    ))
                } else {
                    Err(format!(
                        "Could not restore session: {error}. Damaged snapshots are preserved with a .damaged extension on the next recovery write."
                    ))
                }
            }
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok((Session::default(), None)),
        Err(e) => Err(format!("Could not read session: {e}")),
    }
}
pub fn save(session: &Session) -> Result<(), String> {
    let path = path().ok_or("No configuration directory is available")?;
    save_at(session, &path)
}
fn save_at(session: &Session, path: &std::path::Path) -> Result<(), String> {
    std::fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
    // Keep the previous valid recovery snapshot as a second line of defense.
    if path.exists() {
        let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
        if serde_json::from_slice::<Session>(&bytes).is_ok() {
            let previous = std::str::from_utf8(&bytes).map_err(|e| e.to_string())?;
            crate::document::write(&path.with_extension("json.bak"), previous, None)?;
        } else {
            // Preserve corrupt input as evidence, without replacing a valid backup.
            let mut recovery = tempfile::Builder::new()
                .prefix("session-")
                .suffix(".damaged")
                .tempfile_in(path.parent().unwrap())
                .map_err(|e| e.to_string())?;
            std::io::Write::write_all(&mut recovery, &bytes).map_err(|e| e.to_string())?;
            recovery.keep().map_err(|e| e.to_string())?;
        }
    }
    crate::document::write(
        path,
        &serde_json::to_string(session).map_err(|e| e.to_string())?,
        None,
    )
}

/// Hold for the application lifetime so two instances cannot overwrite recovery.
pub fn lock() -> Result<std::fs::File, Box<dyn std::error::Error>> {
    let path = path().ok_or("No configuration directory is available")?;
    std::fs::create_dir_all(path.parent().unwrap())?;
    let file = std::fs::File::options()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path.with_extension("lock"))?;
    file.try_lock().map_err(|e| {
        format!("Cannot lock the recovery session; writestuff may already be running: {e}")
    })?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn disk_recovery_keeps_previous_snapshot_as_backup() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("session.json");
        let mut session = Session::default();
        session.documents.push(Snapshot {
            id: 42,
            path: None,
            text: "recover this 猫".into(),
            saved: String::new(),
        });
        save_at(&session, &path).unwrap();
        session.documents[0].text = "new version".into();
        save_at(&session, &path).unwrap();
        let current: Session = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        let previous: Session =
            serde_json::from_slice(&std::fs::read(path.with_extension("json.bak")).unwrap())
                .unwrap();
        assert_eq!(current.documents[0].text, "new version");
        assert_eq!(previous.documents[0].text, "recover this 猫");
    }
    #[test]
    fn damaged_session_falls_back_and_does_not_destroy_the_valid_backup() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("session.json");
        let mut session = Session::default();
        session.documents.push(Snapshot {
            id: 7,
            path: None,
            text: "safe".into(),
            saved: String::new(),
        });
        save_at(&session, &path).unwrap();
        save_at(&session, &path).unwrap();
        std::fs::write(&path, "{broken").unwrap();
        let (restored, notice) = load_at(&path).unwrap();
        assert!(notice.is_some());
        assert_eq!(restored.documents[0].text, "safe");
        save_at(&restored, &path).unwrap();
        let backup: Session =
            serde_json::from_slice(&std::fs::read(path.with_extension("json.bak")).unwrap())
                .unwrap();
        assert_eq!(backup.documents[0].text, "safe");
        assert!(std::fs::read_dir(directory.path()).unwrap().any(|entry| {
            entry
                .unwrap()
                .path()
                .extension()
                .is_some_and(|ext| ext == "damaged")
        }));
    }
}
