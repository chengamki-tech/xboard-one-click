# Xboard One Click Security Hardening Implementation Plan

**Goal:** Make the deployment wrapper safer to install and update, while preserving its existing Xboard and Nginx Proxy Manager workflow.

**Architecture:** Keep the shell-based interface, but treat configuration as data, pin the audited Xboard revision and container image manifests, and make firewall exposure opt-in. Add a small shell regression suite that checks syntax, configuration parsing, generated Compose files, and the supply-chain defaults.

**Tech Stack:** Bash, Docker Compose, Git, Python 3 for the existing file transformations, and shell-based tests.

**Spec:** User request to audit `slobys/xboard-one-click`, remove suspected backdoor/supply-chain risks, optimize it, and publish the reviewed copy under the user's GitHub account.

## Global Constraints

- Do not execute `deploy.env` as shell code.
- Do not use floating `latest` image tags in generated Compose files.
- Do not reset an existing Xboard checkout to an unverified branch tip.
- Do not open firewall ports by default from `0.0.0.0/0`.
- Do not commit runtime data or local deployment secrets.

## Review Focus

- A malicious line in `deploy.env` must be ignored rather than executed.
- A changed upstream branch tip or image tag must not silently enter an update.
- A malformed port or CIDR must stop before firewall changes.
- Existing data must survive a normal update and uninstall without purge.
- The generated Compose YAML must remain valid and use the configured ports.

### Task 1: Supply-chain and configuration hardening

**Files:** `install.sh`, `update.sh`, `menu.sh`, `deploy.env.example`, `.gitignore`, `README.md`.

- Replace direct `deploy.env` sourcing with an allowlisted key/value parser.
- Pin Xboard's audited compose commit and both container image manifest digests.
- Add explicit opt-in for custom Xboard sources and source validation.
- Disable automatic firewall opening by default and validate source CIDR.
- Add safer update behavior and document the new controls.

### Task 2: Regression tests and audit artifacts

**Files:** `tests/test_scripts.sh`, `SECURITY.md`.

- Add shell syntax and behavior checks for configuration parsing, Compose generation, and immutable defaults.
- Record the audit scope, findings, and residual trust boundary around prebuilt images.

### Task 3: Verification and publication

- Run the full shell test suite and static scans.
- Create/fork the user's GitHub repository only after local verification.
- Push the hardened branch and report the exact repository and commit.
