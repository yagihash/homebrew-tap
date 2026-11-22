package ghmint

issuer := "https://token.actions.githubusercontent.com"

permissions := {"contents": "write"}

allowed_events := {"push", "workflow_dispatch"}

allow if {
    input.sub == "repo:yagihash@1553908/rivus@1360015006:environment:release"
    input.event_name in allowed_events
    input.job_workflow_ref == "yagihash/rivus/.github/workflows/tagpr.yml@refs/heads/main"
}
