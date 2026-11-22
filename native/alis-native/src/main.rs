mod accel;
mod audio;
mod backlight;
mod calc;
mod clipboard;
mod desktop;
mod gamma;
mod idle;
mod niri;
mod plugins;
mod screencopy;
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
    /// Native qs-rs / inir-accel style accelerators (image-size, cava-config, app-search, thumb-info).
    Accel {
        #[command(subcommand)]
        command: accel::AccelCommand,
    },

    /// Native PipeWire/PulseAudio FFT spectrum analyzer and mic level meter (replaces cava + mic-level-meter.py).
    Audio {
        #[command(subcommand)]
        command: audio::AudioCommand,
    },

    /// Native sysfs + systemd-logind backlight controller replacing brightnessctl.
    Backlight {
        #[command(subcommand)]
        command: backlight::BacklightCommand,
    },

    /// Native scientific math and unit evaluator replacing qalc.
    Calc(calc::CalcArgs),

    /// Native Wayland clipboard daemon and history store replacing cliphist + wl-clipboard.
    Clipboard {
        #[command(subcommand)]
        command: clipboard::ClipboardCommand,
    },

    /// Native parity implementation of scripts/clipboard-store.py.
    ClipboardFilter {
        /// Write the sanitized payload to stdout instead of calling cliphist store.
        #[arg(long)]
        filter: bool,
    },

    /// Desktop configuration writers, portal file dialog, and update checks.
    Desktop {
        #[command(subcommand)]
        command: desktop::DesktopCommand,
    },

    /// Native Wayland gamma / night-light daemon replacing wlsunset.
    Gamma(gamma::GammaArgs),

    /// Native Wayland ext_idle_notifier_v1 + logind idle daemon replacing swayidle.
    Idle {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        args: Vec<String>,
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

    /// Native Wayland screencopy capture helper replacing grim.
    Screencopy(screencopy::ScreencopyArgs),

    /// Native system telemetry reader for CPU, RAM, swap, network, GPU, disk, and temperatures.
    Telemetry(telemetry::TelemetryArgs),

    /// Native translation helper replacing translate-shell (trans).
    Translate(translate::TranslateArgs),
}

fn expects_json_error(command: &Command) -> bool {
    match command {
        Command::Niri { .. } | Command::Plugins { .. } | Command::Telemetry(_) => true,
        Command::Desktop { command } => matches!(
            command,
            desktop::DesktopCommand::SyncIconTheme { .. }
                | desktop::DesktopCommand::SyncFonts { .. }
                | desktop::DesktopCommand::SetKdeConfig { .. }
        ),
        _ => false,
    }
}

fn run(args: Args) -> Result<i32> {
    match args.command {
        Command::Accel { command } => accel::run(command),
        Command::Audio { command } => audio::run(command),
        Command::Backlight { command } => backlight::run(command),
        Command::Calc(args) => calc::run(args),
        Command::Clipboard { command } => clipboard::run_command(command),
        Command::ClipboardFilter { filter } => clipboard::run(filter),
        Command::Desktop { command } => match desktop::run(command)? {
            desktop::DesktopOutcome::Json(value) => {
                println!("{}", serde_json::to_string(&value)?);
                Ok(0)
            }
            desktop::DesktopOutcome::RawLines { lines, code } => {
                for line in lines {
                    println!("{line}");
                }
                Ok(code)
            }
        },
        Command::Gamma(args) => gamma::run(args),
        Command::Idle { args } => idle::run(&args),
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
        Command::Screencopy(args) => screencopy::run(args),
        Command::Telemetry(args) => {
            let value = telemetry::run(args)?;
            println!("{}", serde_json::to_string(&value)?);
            Ok(0)
        }
        Command::Translate(args) => translate::run(args),
    }
}

fn main() {
    let args = Args::parse();
    let json_errors = expects_json_error(&args.command);
    match run(args) {
        Ok(code) => std::process::exit(code),
        Err(error) => {
            eprintln!("{error:#}");
            if json_errors {
                println!("{}", json!({"error": error.to_string()}));
            }
            std::process::exit(1);
        }
    }
}
