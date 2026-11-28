package ghmint

# One policy for every repository whose release bumps its formula here. Add an allow rule for each such repository: only its
# release workflow on main, in its release environment, may write to this repository. The owner and repository IDs are pinned
# (immutable OIDC subject claims), so a recycled name cannot satisfy a rule.
# https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/

issuer := "https://token.actions.githubusercontent.com"

permissions := {"contents": "write"}

allowed_events := {"push", "workflow_dispatch"}

# yagihash/cage: the bump-tap job of tagpr.yml (Formula/cage.rb).
allow if {
	input.sub == "repo:yagihash@1553908/cage@1475119518:environment:release"
	input.event_name in allowed_events
	input.job_workflow_ref == "yagihash/cage/.github/workflows/tagpr.yml@refs/heads/main"
}

# yagihash/rivus: the bump-tap job of tagpr.yml (Formula/rivus.rb).
allow if {
	input.sub == "repo:yagihash@1553908/rivus@1360015006:environment:release"
	input.event_name in allowed_events
	input.job_workflow_ref == "yagihash/rivus/.github/workflows/tagpr.yml@refs/heads/main"
}
