use std::path::Path;
use winreg::enums::*;
use winreg::RegKey;

pub fn register_uri(uri_scheme: &str, exe_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let classes_root = hkcu.open_subkey_with_flags("Software\\Classes", KEY_ALL_ACCESS)
        .or_else(|_| hkcu.create_subkey("Software\\Classes").map(|(k, _)| k))?;

    let (scheme_key, _) = classes_root.create_subkey(uri_scheme)?;
    scheme_key.set_value("", &format!("URL:{uri_scheme}"))?;
    scheme_key.set_value("URL Protocol", &"")?;

    let (shell_key, _) = scheme_key.create_subkey("shell")?;
    let (open_key, _) = shell_key.create_subkey("open")?;
    let (command_key, _) = open_key.create_subkey("command")?;

    let command = format!("\"{}\" \"%1\"", exe_path.display());
    command_key.set_value("", &command)?;

    Ok(())
}
