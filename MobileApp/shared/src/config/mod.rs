//! 配置模型模块：服务器连接配置的 YAML 持久化与 CRUD。
//!
//! 存储位置为 `<filesDir>/servers.yaml`（`filesDir` 由原生层在 `tmInit` 时传入），
//! 环境相关配置一律走配置文件，不得 hardcode。FFI 边界使用 JSON 字符串
//! （对齐契约 `tmConfigList` / `tmConfigSave` / `tmConfigDelete`）。

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard, OnceLock};

/// 一台目标服务器的连接配置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ServerProfile {
    /// 配置名称（UI 展示与覆盖判重用，唯一键）
    pub name: String,
    /// 服务器主机名或 IP
    pub host: String,
    /// SSH 端口，默认 22
    #[serde(default = "default_port")]
    pub port: u16,
    /// 登录用户名
    pub username: String,
    /// 登录密码（MVP 仅支持密码认证，明文落盘；加密存储为后续遗留项）
    #[serde(default)]
    pub password: String,
}

fn default_port() -> u16 {
    22
}

/// 配置存储：内存镜像 + YAML 落盘。
pub(crate) struct ConfigStore {
    path: PathBuf,
    pub(crate) servers: Vec<ServerProfile>,
}

static STORE: OnceLock<Mutex<ConfigStore>> = OnceLock::new();

/// 初始化配置存储：加载 `<filesDir>/servers.yaml`（不存在则视为空配置）。
/// 允许重复调用（测试换目录 / 原生层重启），后者覆盖前者。
pub fn init(files_dir: &str) -> Result<(), String> {
    let path = PathBuf::from(files_dir).join("servers.yaml");
    let servers = match std::fs::read_to_string(&path) {
        Ok(content) if !content.trim().is_empty() => serde_yaml::from_str(&content)
            .map_err(|e| format!("解析 {} 失败：{e}", path.display()))?,
        Ok(_) => Vec::new(),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
        Err(e) => return Err(format!("读取 {} 失败：{e}", path.display())),
    };
    let fresh = ConfigStore { path, servers };
    match STORE.get() {
        Some(mutex) => {
            *mutex.lock().map_err(|e| format!("配置存储锁中毒：{e}"))? = fresh;
        }
        None => {
            let _ = STORE.set(Mutex::new(fresh));
        }
    }
    Ok(())
}

pub(crate) fn store() -> Result<MutexGuard<'static, ConfigStore>, String> {
    STORE
        .get()
        .ok_or_else(|| "配置存储未初始化（需先调用 tmInit）".to_string())?
        .lock()
        .map_err(|e| format!("配置存储锁中毒：{e}"))
}

/// 契约 `tmConfigList`：返回全部服务器配置的 JSON 数组字符串。
pub fn list_json() -> Result<String, String> {
    let guard = store()?;
    serde_json::to_string(&guard.servers).map_err(|e| format!("序列化配置失败：{e}"))
}

/// 契约 `tmConfigSave`：按 name 新增或覆盖一条配置，并落盘。
pub fn save_json(json: &str) -> Result<(), String> {
    let profile: ServerProfile =
        serde_json::from_str(json).map_err(|e| format!("解析配置 JSON 失败：{e}"))?;
    if profile.name.trim().is_empty() {
        return Err("配置名称不能为空".to_string());
    }
    let mut guard = store()?;
    match guard.servers.iter_mut().find(|s| s.name == profile.name) {
        Some(existing) => *existing = profile,
        None => guard.servers.push(profile),
    }
    persist(&guard)
}

/// 契约 `tmConfigDelete`：按 name 删除一条配置，并落盘。
pub fn delete(name: &str) -> Result<(), String> {
    let mut guard = store()?;
    guard.servers.retain(|s| s.name != name);
    persist(&guard)
}

/// 移动一条配置并持久化新顺序。
pub fn move_item(from: usize, to: usize) -> Result<(), String> {
    let mut guard = store()?;
    if from >= guard.servers.len() || to >= guard.servers.len() {
        return Err(format!(
            "配置排序索引越界：from={from}, to={to}, len={}",
            guard.servers.len()
        ));
    }
    if from == to {
        return Ok(());
    }

    let original = guard.servers.clone();
    let profile = guard.servers.remove(from);
    guard.servers.insert(to, profile);
    if let Err(error) = persist(&guard) {
        guard.servers = original;
        return Err(error);
    }
    Ok(())
}

/// 把内存镜像写回 YAML 文件。
pub(crate) fn persist(store: &ConfigStore) -> Result<(), String> {
    let content =
        serde_yaml::to_string(&store.servers).map_err(|e| format!("序列化 YAML 失败：{e}"))?;
    std::fs::write(&store.path, content)
        .map_err(|e| format!("写入 {} 失败：{e}", store.path.display()))
}

/// 测试辅助：判断存储是否已初始化。
#[cfg(test)]
fn initialized() -> bool {
    STORE.get().is_some()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// STORE 是全局单例，配置测试必须串行执行
    static TEST_LOCK: Mutex<()> = Mutex::new(());

    /// 每个用例使用独立临时目录，避免互相污染。
    fn 初始化临时目录(tag: &str) -> String {
        let dir = std::env::temp_dir().join(format!(
            "termirror_config_test_{}_{}",
            tag,
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        init(dir.to_str().unwrap()).unwrap();
        dir.to_string_lossy().into_owned()
    }

    #[test]
    fn 配置增删查与落盘回读() {
        let _guard = TEST_LOCK.lock().unwrap();
        let dir = 初始化临时目录("crud");
        assert!(initialized());
        assert_eq!(list_json().unwrap(), "[]");

        save_json(
            r#"{"name":"办公机","host":"10.0.0.2","port":22,"username":"medie","password":"pw"}"#,
        )
        .unwrap();
        save_json(
            r#"{"name":"家用机","host":"192.168.1.2","port":2222,"username":"xp","password":""}"#,
        )
        .unwrap();
        let list: Vec<ServerProfile> = serde_json::from_str(&list_json().unwrap()).unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].name, "办公机");
        assert_eq!(list[1].port, 2222);

        // 同名覆盖
        save_json(
            r#"{"name":"办公机","host":"10.0.0.3","port":22,"username":"medie","password":"pw2"}"#,
        )
        .unwrap();
        let list: Vec<ServerProfile> = serde_json::from_str(&list_json().unwrap()).unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].host, "10.0.0.3");

        // YAML 文件已落盘且可回读
        let content = std::fs::read_to_string(format!("{dir}/servers.yaml")).unwrap();
        let from_disk: Vec<ServerProfile> = serde_yaml::from_str(&content).unwrap();
        assert_eq!(from_disk.len(), 2);

        // 删除
        delete("家用机").unwrap();
        let list: Vec<ServerProfile> = serde_json::from_str(&list_json().unwrap()).unwrap();
        assert_eq!(list.len(), 1);
        delete("不存在").unwrap(); // 删除不存在的名字不报错
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn 非法json与空名称报错() {
        let _guard = TEST_LOCK.lock().unwrap();
        let dir = 初始化临时目录("invalid");
        assert!(save_json("不是json").is_err());
        assert!(
            save_json(r#"{"name":"  ","host":"h","port":22,"username":"u","password":""}"#)
                .is_err()
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn 移动配置后持久化顺序() {
        let _guard = TEST_LOCK.lock().unwrap();
        let dir = 初始化临时目录("move");
        for name in ["甲", "乙", "丙"] {
            save_json(&format!(
                r#"{{"name":"{name}","host":"host","port":22,"username":"user","password":""}}"#
            ))
            .unwrap();
        }

        move_item(0, 2).unwrap();
        let names = || {
            serde_json::from_str::<Vec<ServerProfile>>(&list_json().unwrap())
                .unwrap()
                .into_iter()
                .map(|profile| profile.name)
                .collect::<Vec<_>>()
        };
        assert_eq!(names(), vec!["乙", "丙", "甲"]);

        init(&dir).unwrap();
        assert_eq!(names(), vec!["乙", "丙", "甲"]);
        assert!(move_item(3, 0).is_err());
        assert_eq!(names(), vec!["乙", "丙", "甲"]);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
