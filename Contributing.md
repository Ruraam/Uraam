# Contributing to URAAM

Thank you for helping improve URAAM. Contributions may include bug fixes, tests, documentation, translations and carefully reviewed Android package profiles.

## Before opening a pull request

1. Search existing issues and pull requests for related work.
2. Describe the problem and the expected behavior.
3. Keep changes focused; avoid unrelated formatting or path changes.
4. Update documentation when user-visible behavior, dependencies, menu prompts or data paths change.
5. Add regression tests for safety-sensitive behavior.
6. Never claim real-device validation when only mocks or CI were used.

## Shell changes

For changes to `uraam.sh` or shell tests, run:

```bash
bash -n uraam.sh
bash -n tests/test-preview-dry-run.sh
bash -n tests/test-interrupted-process.sh
shellcheck --severity=error uraam.sh tests/test-preview-dry-run.sh tests/test-interrupted-process.sh
bash tests/test-preview-dry-run.sh
bash tests/test-interrupted-process.sh
```

If UAD metadata is modified, also run:

```bash
python3 tests/validate_uad_metadata.py
```

Do not weaken a safety check merely to make a test pass. A mock must model the intended boundary precisely and must not replace production logic under test.

## Debloat profile contributions

Profile files belong in `Configs/debloat/`. Follow the schema and policy in [Configs/debloat/README.md](Configs/debloat/README.md), and validate JSON before submitting.

A profile is a suggested package list, not a universal removal guarantee. Include the device family, model, Android version and firmware context in the description or pull request. Test on the intended device and clearly state what was tested.

Do not label a profile Safe solely because a package is marked Recommended by UAD-NG. Do not submit bulk Google, AOSP, Carrier or Misc removal lists as universal profiles.

## UAD-NG metadata

The bundled catalogue is pinned to an upstream commit. Any update must include:

- the exact upstream revision and source URL;
- an updated `Configs/uad/source.json` manifest;
- the upstream attribution/licence;
- the intentional validator revision/count update;
- a review of changed classifications and affected profiles.

See [the UAD-NG review policy](Docs/UAD-NG-review-catalog.md).

## Documentation contributions

- Write instructions for the current implementation, not historical versions.
- Prefer exact commands and current repository-relative links.
- State platform-specific requirements explicitly.
- Explain destructive effects, confirmation prompts and recovery paths.
- Separate verified behavior from assumptions and limitations.
- Avoid absolute claims such as “100% safe”, “risk-free” or “guaranteed reversible”.

## Pull request checklist

- [ ] Scope and motivation are clear.
- [ ] Existing paths and user data layouts are preserved unless a migration is explicitly included.
- [ ] Shell syntax and relevant tests pass.
- [ ] Safety-sensitive paths have regression coverage.
- [ ] Documentation and examples match the code.
- [ ] Real-device testing is reported accurately, including device model, Android version and backend.
