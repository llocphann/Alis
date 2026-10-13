mod clipboard;
mod desktop;
mod niri;

use anyhow::Result;
use clap::{Parser, Subcommand};
use serde_json::json;

#[derive(Debug, Parser)]
#[command(about = "Dormant one-shot native helpers for Alis")]
struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Native parity implementation of scripts/clipboard-store.py.
    ClipboardFilter {
        /// Write the sanitized payload to stdout instead of calling cliphist store.
        #[arg(long)]
        filter: bool,
    },

    /// Desktop configuration writers replacing Python configparser subprocesses.
    Desktop {
        #[command(subcommand)]
        command: desktop::DesktopCommand,
    },

    /// Native Niri configuration/query implementation staged beside niri-config.py.
    Niri {
        #[command(subcommand)]
        command: niri::NiriCommand,
    },
}

fn run() -> Result<i32> {
    let args = Args::parse();
    match args.command {
        Command::ClipboardFilter { filter } => clipboard::run(filter),
        Command::Desktop { command } => {
            let value = desktop::run(command)?;
            println!("{}", serde_json::to_string(&value)?);
            Ok(0)
        }
        Command::Niri { command } => {
            let outcome = niri::run(command)?;
            println!("{}", serde_json::to_string(&outcome.value)?);
            Ok(outcome.code)
        }
    }
}

fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(error) => {
            println!("{}", json!({"error": error.to_string()}));
            std::process::exit(1);
        }
    }
}
