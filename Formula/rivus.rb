class Rivus < Formula
  desc "Cross-file taint analysis query engine for Go, Dart and Rust"
  homepage "https://github.com/yagihash/rivus"
  url "https://github.com/yagihash/rivus/archive/refs/tags/v0.0.6.tar.gz"
  sha256 "d698c93dc24069525356597f4fda24b26ef605dd7c44c792ba9a41f511bd1f58"
  license "Apache-2.0"
  head "https://github.com/yagihash/rivus.git", branch: "main"

  depends_on "rustup" => :build
  depends_on "dart-sdk"
  depends_on "go"
  depends_on :macos

  def install
    toolchain = "nightly-2026-11-15"
    pinned = (buildpath/"extractor/rust/rust-toolchain.toml").read[/^channel\s*=\s*"([^"]+)"/, 1]
    odie "the pinned toolchain is #{pinned}, expected #{toolchain}" if pinned != toolchain

    system "go", "build", *std_go_args(output: libexec/"bin/rivus", ldflags: "-s -w -X main.versionStamp=#{version}"), "./cmd/rivus"

    dart_dir = libexec/"dart"
    dart_dir.mkpath
    cp_r %w[extractor/dart/bin extractor/dart/lib extractor/dart/pubspec.yaml extractor/dart/pubspec.lock], dart_dir
    cd dart_dir do
      system "dart", "pub", "get", "--enforce-lockfile"
      system "dart", "compile", "kernel", "bin/rivus_dart.dart", "-o", "rivus_dart.dill"
      rm_r ".dart_tool"
    end
    (bin/"rivus-dart").write <<~SH
      #!/bin/sh
      exec "#{formula_opt_bin("dart-sdk")}/dart" "#{dart_dir}/rivus_dart.dill" "$@"
    SH

    # Rust: the pinned nightly lives outside the keg, in var/rivus/rustup, so that Homebrew's
    # relocation does not touch it (it cannot rewrite the dylib IDs of rustup's libraries) and an
    # upgrade does not download it again. The extractor is built with it, so the rpath recorded
    # by cargo points at the toolchain's final location.
    rust_home = var/"rivus/rustup"
    arch = Hardware::CPU.arm? ? "aarch64" : "x86_64"
    tc = rust_home/"toolchains/#{toolchain}-#{arch}-apple-darwin"
    ENV["RUSTUP_HOME"] = rust_home
    rust_home.mkpath
    toolchain_ready = (tc/"bin/cargo").exist? && Dir[tc/"lib/librustc_driver-*.dylib"].any?
    unless toolchain_ready
      system formula_opt_bin("rustup")/"rustup", "toolchain", "install", toolchain,
             "--profile", "minimal", "-c", "rustc-dev", "-c", "llvm-tools", "-c", "rust-src", "--no-self-update"
    end

    home = buildpath/"home"
    mkdir_p home
    with_env(
      SDKROOT:          MacOS.sdk_path.to_s,
      PATH:             "#{tc}/bin:/usr/bin:/bin",
      HOME:             home.to_s,
      RUSTUP_TOOLCHAIN: toolchain,
      CARGO_HOME:       (buildpath/"cargo").to_s,
      CARGO_TARGET_DIR: (buildpath/"target").to_s,
    ) do
      system tc/"bin/cargo", "install", "--path", "extractor/rust", "--locked", "--root", libexec/"rust-ext"
    end
    # Drop the toolchains of other versions (only inside var/rivus/rustup) and rustup's scratch space.
    %w[toolchains update-hashes].each do |dir|
      next unless (rust_home/dir).directory?

      (rust_home/dir).children.each { |child| rm_r child if child.basename.to_s != tc.basename.to_s }
    end
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
      Installing downloads about 1.1 GB from static.rust-lang.org and crates.io.
      The pinned Rust toolchain is kept in #{var}/rivus, outside the keg, so
      `brew uninstall rivus` does not remove it. To remove it:
        rm -rf "#{var}/rivus"
      Rust analysis fetches the dependencies of the target project from crates.io.

      Dart analysis runs a kernel snapshot built against the dart-sdk that was
      installed at build time. If Dart analysis fails with a kernel version
      mismatch after dart-sdk has been updated, run:
        brew reinstall rivus

      Run `dart pub get` in the target project before Dart analysis.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/rivus version")
    assert_match "analyze", shell_output("#{bin}/rivus help 2>&1")

    # The Rust extractor starts (no dyld error); it exits with 2 for a directory that is not there.
    output = shell_output("#{libexec}/rust-ext/bin/rivus-rust #{testpath}/none 2>&1", 2)
    refute_match "dyld", output
    assert_match "rivus-rust:", output
  end
end
