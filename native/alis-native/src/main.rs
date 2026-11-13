mod backlight;
mod calc;
mod clipboard;
mod desktop;
mod niri;
mod plugins;
mod telemetry;
mod translate;

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
    /// Native sysfs + systemd-logind backlight controller replacing brightnessctl.
    Backlight {
        #[command(subcommand)]
        command: backlight::BacklightCommand,
    },

    /// Native scientific math and unit evaluator replacing qalc.
    Calc(calc::CalcArgs),

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

    /// Native plugin manifest scanner replacing scripts/scan-plugins.py.
    Plugins {
        #[command(subcommand)]
        command: plugins::PluginsCommand,
    },

    /// Native system telemetry reader for CPU, RAM, swap, network, GPU, disk, and temperatures.
    Telemetry(telemetry::TelemetryArgs),

    /// Native translation helper replacing translate-shell (trans).
    Translate(translate::TranslateArgs),
}

fn run() -> Result<i32> {
    let args = Args::parse();
    match args.command {
        Command::Backlight { command } => backlight::run(command),
        Command::Calc(args) => calc::run(args),
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
        Command::Plugins { command } => {
            let value = plugins::run(command)?;
            println!("{}", serde_json::to_string(&value)?);
            Ok(0)
        }
        Command::Telemetry(args) => {
            let value = telemetry::run(args)?;
            println!("{}", serde_json::to_string(&value)?);
            Ok(0)
        }
        Command::Translate(args) => translate::run(args),
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
