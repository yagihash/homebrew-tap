class Cage < Formula
  desc "Harness that runs coding agents in a sandbox, each as a GitHub App of its own"
  homepage "https://github.com/yagihash/cage"
  url "https://github.com/yagihash/cage/releases/download/v0.1.0/cage_0.1.0_source.tar.gz"
  sha256 "44839c96612689ab6b94d5980c6e48462924f713ff5d2022268bca141b179aa8"
  license "MIT"
  head "https://github.com/yagihash/cage.git", branch: "main"

  depends_on "go" => :build
  depends_on :macos

  def install
    # As scripts/build-release-archives.sh builds the release archive: one Go binary, git-remote-cage as a link to it
    # (cage acts as the remote helper by that name, ADR-016), and cage-se (Swift, the Secure Enclave helper) beside
    # cage, where cage looks for it first.
    ENV["CGO_ENABLED"] = "0"
    go_ldflags = "-X github.com/yagihash/cage/internal/cli.Version=#{version}"
    system "go", "build", *std_go_args(output: bin/"cage", ldflags: go_ldflags), "./cmd/cage"
    bin.install_symlink "cage" => "git-remote-cage"
    system "swiftc", "-O", "-target", "arm64-apple-macos14", "se/cage-se.swift", "-o", bin/"cage-se"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cage version")

    # By the name git-remote-cage, cage is the remote helper: it refuses a URL that is not a GitHub repository.
    output = shell_output("#{bin}/git-remote-cage origin https://example.com/x 2>&1", 2)
    assert_match "is not a GitHub repository URL", output

    assert_predicate bin/"cage-se", :executable?
  end
end
