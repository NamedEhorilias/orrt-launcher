use std::{
    env::{self, current_exe},
    fs::{self, File},
    io::{self, Cursor},
    path::PathBuf,
};

use crate::{
    config::{APP_NAME, INSTALL_FOLDER, POST_INSTALL_URL, PROTOCOL, SETUP},
    utils,
};
use anyhow::Result;
use anyhow::anyhow;
use reqwest::Client;
use zip::ZipArchive;

pub async fn is_up_to_update() -> Result<(bool, String)> {
    let client = Client::new();
    let latest_version = match client.get(format!("{SETUP}/version")).send().await {
        Ok(res) if res.status().is_success() => res.text().await?.trim().to_string(),
        _ => "v1.0.0".to_string(),
    };
    let local_appdata = env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".to_string());
    let install_dir = PathBuf::from(local_appdata).join(INSTALL_FOLDER);
    if fs::read_to_string(install_dir.join("version"))
        .map(|x| x.trim() == latest_version)
        .unwrap_or(false)
    {
        Ok((true, latest_version))
    } else {
        Ok((false, latest_version))
    }
}

#[allow(clippy::too_many_lines, reason = "code is more readable as it is")]
pub async fn bootstrap() -> Result<()> {
    let client = Client::new();
    let latest_version = match client.get(format!("{SETUP}/version")).send().await {
        Ok(res) if res.status().is_success() => res.text().await?.trim().to_string(),
        _ => "v1.0.0".to_string(),
    };
    let local_appdata = env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".to_string());
    let install_dir = PathBuf::from(local_appdata).join(INSTALL_FOLDER);
    fs::create_dir_all(&install_dir)?;
    env::set_current_dir(&install_dir)?;
    if fs::read_to_string("version")
        .map(|x| x.trim() == latest_version)
        .unwrap_or(false)
    {
        paris::info!("Latest version {latest_version} installed. Nothing to do.");
        let _ = open::that(POST_INSTALL_URL);
        return Ok(());
    }
    paris::info!("Updating {APP_NAME}");
    if let Ok(years_res) = client.get(format!("{SETUP}/available-years.txt")).send().await {
        if years_res.status().is_success() {
            let years = years_res.text().await?;
            for year in years.lines() {
                let year = year.trim();
                if year.is_empty() {
                    continue;
                }
                paris::info!("Downloading {year} client");
                if let Ok(dl) = client.get(format!("{SETUP}/{latest_version}-ProjectXApp{year}.zip")).send().await {
                    if dl.status().is_success() {
                        let bytes = dl.bytes().await?;
                        paris::success!("Download complete");
                        paris::info!("Extracting client");
                        let client_path = PathBuf::from(format!("Versions/{latest_version}/{year}"));
                        fs::create_dir_all(&client_path)?;
                        if let Ok(mut zip) = ZipArchive::new(Cursor::new(bytes)) {
                            for i in 0..zip.len() {
                                let Ok(mut file) = zip.by_index(i) else { continue; };
                                let Some(path) = file.enclosed_name() else { continue; };
                                let path = client_path.join(path);
                                if file.is_dir() {
                                    let _ = fs::create_dir_all(&path);
                                } else {
                                    if let Some(parent) = path.parent() {
                                        let _ = fs::create_dir_all(parent);
                                    }
                                    if let Ok(mut fsfile) = File::create(&path) {
                                        let _ = io::copy(&mut file, &mut fsfile);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    let _ = fs::write("version", &latest_version);
    paris::info!("Copying self to folder");
    let launcher_path = install_dir.join("ORRTLauncher.exe");
    let _ = fs::copy(current_exe()?, &launcher_path);
    paris::info!("Setting up URI handlers");
    // Register primary protocol: orrt-player
    let _ = utils::register_uri(PROTOCOL, &launcher_path);
    // Register backwards-compatible protocols: pekora-player and pekora2-player
    let _ = utils::register_uri("pekora-player", &launcher_path);
    let _ = utils::register_uri("pekora2-player", &launcher_path);
    paris::success!("ORRT Bootstrap finished successfully!");
    let _ = open::that(POST_INSTALL_URL);
    Ok(())
}
