#![warn(clippy::pedantic)]
use std::{
    env,
    io::{self, Write},
    thread,
    time::Duration,
};



mod bootstrapper;
mod config;
mod launcher;
mod utils;

#[tokio::main]
async fn main() {
    println!("ORRT Launcher - orrt.online");

    let mut args = env::args();
    let _ = args.next();
    match args.next() {
        None => {
            if let Err(err) = bootstrapper::bootstrap().await {
                paris::error!("Error while bootstrapping: {err:?}");
            }
            println!("Press enter to exit");
            let _ = io::stdin().read_line(&mut String::new());
        }
        Some(x) if x.starts_with(config::PROTOCOL) || x.starts_with("pekora-player") || x.starts_with("pekora2-player") => {
            if let Err(err) = launcher::launch(&x).await {
                paris::error!("Error while launching: {err:?}");
                println!("Press enter to exit");
                let _ = io::stdin().read_line(&mut String::new());
            } else {
                println!("Closing in 5 seconds");
                thread::sleep(Duration::from_secs(5));
            }
        }
        _ => {
            paris::error!("Unknown argument(s). Pass 0 arguments to install or update ORRT.");
            thread::sleep(Duration::from_secs(5));
        }
    }
}
