# Recipes

Declarative environment presets (SPEC §5.2, D-003). Initial set:

| Recipe | Purpose |
|---|---|
| `network-research.yaml` | Connectivity diagnostics and traffic inspection |
| `web-security.yaml` | Web application assessment tooling |
| `malware-analysis.yaml` | Static/dynamic inspection of untrusted binaries |
| `digital-forensics.yaml` | Disk and artefact recovery/analysis |
| `osint.yaml` | Open-source intelligence gathering |
| `linux-fundamentals.yaml` | Plain shell for learning Linux |

Schema (shared with `environment.yaml` exported from a session):

```yaml
name: <recipe-id>
base: <image>          # e.g. alpine:3.22
packages:              # apk packages installed at environment creation
  - <package>
```

Recipes MUST stay declarative and version-controlled; they are presets, not
scripts. Package availability depends on D-004 (package mirror policy — still
`Proposed`, resolved at P3 / OQ-002).
