use std::env::current_exe;
use std::process::Command;

use anyhow::Result;

use crate::bootstrapper;

struct Args {
    _launch_mode: String,
    client_version: String,
    game_info: String,
    place_launcher_url: String,
}

pub async fn launch(uri: &str) -> Result<()> {
    let (up_to_date, latest_version) = bootstrapper::is_up_to_update().await?;
    if !up_to_date {
        paris::info!("Out ouf date, updating");
        bootstrapper::bootstrap().await?;
    }
    let re = regex::Regex::new(r"(?:orrt-player|pekora-player|pekora2-player):1\+launchmode:([^+]+)\+clientversion:([^+]+)\+gameinfo:([^+]+)\+placelauncherurl:([^+]+)").unwrap();
    let captures = re
        .captures(uri)
        .ok_or_else(|| anyhow::anyhow!("Invalid URI format: {uri}"))?;

    let args = Args {
        _launch_mode: captures.get(1).unwrap().as_str().to_string(),
        client_version: captures.get(2).unwrap().as_str().to_string(),
        game_info: captures.get(3).unwrap().as_str().to_string(),
        place_launcher_url: captures.get(4).unwrap().as_str().to_string(),
    };
    paris::info!("Starting {}", args.client_version);
    let exe_path = current_exe()?;
    let install_path = exe_path.parent().unwrap();

    let negotiate_url = format!("{}/Login/Negotiate.ashx", crate::config::BASE_URL);

    // Support both RobloxPlayerBeta.exe and ProjectXPlayerBeta.exe
    let version_dir = install_path
        .join("Versions")
        .join(&latest_version)
        .join(&args.client_version);
    
    let mut exe_to_run = version_dir.join("RobloxPlayerBeta.exe");
    if !exe_to_run.exists() {
        let alt = version_dir.join("ProjectXPlayerBeta.exe");
        if alt.exists() {
            exe_to_run = alt;
        }
    }

    Command::new(&exe_to_run)
        .arg("--play")
        .arg("-a")
        .arg(&negotiate_url)
        .arg("-t")
        .arg(args.game_info)
        .arg("-j")
        .arg(args.place_launcher_url)
        .spawn()?;
    paris::success!("Started ORRT ({})", exe_to_run.display());
    Ok(())
}
