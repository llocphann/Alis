## Python Virtual Environment (Optional)

Core Alis runtime features — including Material You palette extraction,
thumbnail generation, image region detection, album cover color extraction,
wallpaper effects, clipboard history, audio FFT spectrum, night light, idle
management, and screencopy — run natively through Alis's compiled Rust helpers
(`alis-native`, `alis-theme`, `alis-inputd`, `alis-mpdd`).

No `.venv` or `uv` installation is required for the core shell runtime.

### Optional AI Cutout (`wallfx`)

Optional AI wallpaper foreground cutout features manage their own isolated
opt-in Python environment on demand when explicitly enabled by the user.
