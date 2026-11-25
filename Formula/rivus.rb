class Rivus < Formula
  desc "Cross-file taint analysis query engine for Go, Dart and Rust"
  homepage "https://github.com/yagihash/rivus"
  url "https://github.com/yagihash/rivus/releases/download/v0.0.19/rivus_0.0.19_source.tar.gz"
  sha256 "80b9c935c9dc6dcddb0aadbafe8ecb129d1d99aff6b13b273df5e5dfd43b3b2b"
  license "Apache-2.0"
  head "https://github.com/yagihash/rivus.git", branch: "main"

  depends_on "rustup" => :build
  depends_on "dart-sdk"
  depends_on "go"
  depends_on :macos

  def install
    # The Rust nightly is pinned by rivus itself: extractor/rust/rust-toolchain.toml in the source tree is the single
    # source of truth, so this formula holds no date and a release that bumps the nightly needs no change here.
    toolchain_file = buildpath/"extractor/rust/rust-toolchain.toml"
    odie "extractor/rust/rust-toolchain.toml is missing from the source tree" unless toolchain_file.file?
    toolchain = toolchain_file.read[/^channel\s*=\s*"([^"]*)"/, 1]
    odie "extractor/rust/rust-toolchain.toml has no `channel = \"...\"` line" if toolchain.nil?
    odie "the `channel` in extractor/rust/rust-toolchain.toml is empty" if toolchain.empty?
    unless toolchain.match?(/\Anightly-\d{4}-\d{2}-\d{2}\z/)
      odie "the `channel` in extractor/rust/rust-toolchain.toml is #{toolchain.inspect}, expected nightly-YYYY-MM-DD"
    end

    # The hashes of the extractors' source (scripts/extractor-hash, as in scripts/build-release-archives.sh) are built
    # into rivus and into each extractor, so that rivus can tell whether an extractor matches its own source.
    # A release made before the script existed has no such file; the hashes stay empty and are not passed.
    hash_script = buildpath/"scripts/extractor-hash"
    rust_hash = ""
    dart_hash = ""
    if hash_script.directory?
      rust_hash = Utils.safe_popen_read("go", "run", "./scripts/extractor-hash", "rust").strip
      dart_hash = Utils.safe_popen_read("go", "run", "./scripts/extractor-hash", "dart").strip
      odie "scripts/extractor-hash printed an empty hash" if rust_hash.empty? || dart_hash.empty?
    end
    go_ldflags = "-s -w -X main.versionStamp=#{version}"
    unless rust_hash.empty?
      go_ldflags += " -X main.rustSourceHash=#{rust_hash} -X main.dartSourceHash=#{dart_hash}"
    end

    system "go", "build", *std_go_args(output: libexec/"bin/rivus", ldflags: go_ldflags), "./cmd/rivus"

    # Dart: the extractor is compiled to a native executable (about 0.2-0.6 s to start, against 1.6-3.8 s for a kernel
    # snapshot). The executable reads the `dart:*` sources of a Dart SDK at run time, so it is not self-contained:
    # the wrappers below put dart-sdk's bin first on PATH, where rivus finds the SDK from the `dart` it finds there.
    cd "extractor/dart" do
      system "dart", "pub", "get", "--enforce-lockfile"
      dart_defines = dart_hash.empty? ? [] : ["-DRIVUS_SRC_HASH=#{dart_hash}"]
      system "dart", "compile", "exe", *dart_defines, "bin/rivus_dart.dart", "-o", libexec/"rivus-dart"
    end
    dart_path = formula_opt_bin("dart-sdk")
    (bin/"rivus-dart").write <<~SH
      #!/bin/sh
      export PATH="#{dart_path}:$PATH"
      exec "#{libexec}/rivus-dart" "$@"
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
    rust_env = rust_hash.empty? ? {} : { RIVUS_EXTRACTOR_SRC_HASH: rust_hash }
    with_env(
      **rust_env,
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
      export PATH="#{dart_path}:$PATH"
      export RIVUS_DART_EXTRACTOR="${RIVUS_DART_EXTRACTOR:-#{libexec}/rivus-dart}"
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

      Dart analysis runs an executable compiled at install time (#{libexec}/rivus-dart).
      It reads the Dart SDK's `dart:*` sources at run time, from the dart-sdk
      formula (the `rivus` command puts its bin first on PATH; RIVUS_DART_SDK
      overrides it). The executable does not embed the SDK, so it is not tied to
      the SDK's kernel version. Not verified: whether a much newer dart-sdk
      changes the analysis. To check, run `rivus sites -lang dart` on a small
      project after `brew upgrade dart-sdk`, and `brew reinstall rivus` if it
      fails or differs.

      Run `dart pub get` in the target project before Dart analysis.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/rivus version")
    assert_match "analyze", shell_output("#{bin}/rivus help 2>&1")

    # The Dart extractor runs through the wrapper (it needs dart-sdk's sources) and finds a call in a small project.
    (testpath/"dart/lib").mkpath
    (testpath/"dart/pubspec.yaml").write "name: demo\nenvironment:\n  sdk: ^3.8.0\n"
    (testpath/"dart/lib/main.dart").write <<~DART
      import "dart:io";
      void main(List<String> a) {
        Process.run("sh", ["-c", a.first]);
      }
    DART
    sites = shell_output("#{bin}/rivus sites -lang dart -C #{testpath}/dart")
    assert_match "dart:io#Process.run", sites

    # The Rust extractor starts (no dyld error); it exits with 2 for a directory that is not there.
    output = shell_output("#{libexec}/rust-ext/bin/rivus-rust #{testpath}/none 2>&1", 2)
    refute_match "dyld", output
    assert_match "rivus-rust:", output
  end
end
