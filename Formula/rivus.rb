class Rivus < Formula
  desc "Cross-file taint analysis query engine for Go, Dart and Rust"
  homepage "https://github.com/yagihash/rivus"
  url "https://github.com/yagihash/rivus/archive/refs/tags/v0.0.1.tar.gz"
  sha256 "92e2e1793ef4844f2201c45d4fe0ff6af8701d09690ecafb7ee236b694f795dc"
  license "Apache-2.0"
  head "https://github.com/yagihash/rivus.git", branch: "main"

  depends_on :macos
  depends_on "dart-sdk"
  depends_on "go"
  depends_on "rustup" => :build

  def install
    toolchain = "nightly-2026-11-15"
    pinned = (buildpath/"extractor/rust/rust-toolchain.toml").read[/^channel\s*=\s*"([^"]+)"/, 1]
    odie "the pinned toolchain is #{pinned}, expected #{toolchain}" if pinned != toolchain

    system "go", "build", *std_go_args(output: libexec/"bin/rivus", ldflags: "-s -w -X main.versionStamp=#{version}"), "./cmd/rivus"

    libexec.install "extractor/dart/bin", "extractor/dart/lib", "extractor/dart/pubspec.yaml", "extractor/dart/pubspec.lock"
    cd libexec do
      system "dart", "pub", "get", "--enforce-lockfile"
      system "dart", "compile", "kernel", "bin/rivus_dart.dart", "-o", "rivus_dart.dill"
      rm_r ".dart_tool"
    end
    (bin/"rivus-dart").write <<~SH
      #!/bin/sh
      exec "#{Formula["dart-sdk"].opt_bin}/dart" "#{libexec}/rivus_dart.dill" "$@"
    SH

    # Rust: the nightly toolchain and the extractor are built inside the keg, so that
    # the rpaths recorded by cargo point at the toolchain's final location.
    rust_home = libexec/"rustup"
    cargo_home = libexec/"cargo"
    arch = Hardware::CPU.arm? ? "aarch64" : "x86_64"
    tc = rust_home/"toolchains/#{toolchain}-#{arch}-apple-darwin"
    ENV["RUSTUP_HOME"] = rust_home
    ENV["CARGO_HOME"] = cargo_home
    system Formula["rustup"].opt_bin/"rustup", "toolchain", "install", toolchain,
           "--profile", "minimal", "-c", "rustc-dev", "-c", "llvm-tools", "-c", "rust-src", "--no-self-update"

    home = buildpath/"home"
    mkdir_p home
    with_env(
      SDKROOT:             MacOS.sdk_path.to_s,
      PATH:                "#{tc}/bin:/usr/bin:/bin",
      HOME:                home.to_s,
      RUSTUP_TOOLCHAIN:    toolchain,
      CARGO_HOME:          (buildpath/"cargo").to_s,
      CARGO_TARGET_DIR:    (buildpath/"target").to_s,
    ) do
      system tc/"bin/cargo", "install", "--path", "extractor/rust", "--locked", "--root", libexec/"rust-ext"
    end
    rm_r cargo_home
    rm_r rust_home/"downloads" if (rust_home/"downloads").exist?
    rm_r rust_home/"tmp" if (rust_home/"tmp").exist?

    (bin/"rivus").write <<~SH
      #!/bin/sh
      export RIVUS_RUST_TOOLCHAIN_DIR="${RIVUS_RUST_TOOLCHAIN_DIR:-#{tc}}"
      export RIVUS_RUST_EXTRACTOR="${RIVUS_RUST_EXTRACTOR:-#{libexec}/rust-ext/bin/rivus-rust}"
      exec "#{libexec}/bin/rivus" "$@"
    SH
  end

  def caveats
    <<~EOS
      Rust analysis runs under the macOS sandbox (sandbox-exec).
      Installing downloads about 1.1 GB from static.rust-lang.org and crates.io
      and keeps it in this keg.
      Rust analysis fetches the dependencies of the target project from crates.io.

      Dart analysis runs a kernel snapshot built against the dart-sdk that was
      installed at build time. If Dart analysis fails with a kernel version
      mismatch after dart-sdk has been updated, run:
        brew reinstall rivus

      Run `dart pub get` in the target project before Dart analysis.
    EOS
  end

  test do
    assert_match "0.0.1", shell_output("#{bin}/rivus version")
    assert_match "analyze", shell_output("#{bin}/rivus help 2>&1")
  end
end
