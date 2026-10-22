## Summary

Describe the change and the problem it solves.

## Testing

- [ ] `./scripts/test.sh` passes, or the reason it cannot be run is explained.
- [ ] New regression tests cover security-sensitive behavior.
- [ ] No generated build artifacts, credentials, private archives, or logs are
      included.

## Checklist

- [ ] The change preserves Finder-driven extraction without a main window.
- [ ] Passwords are not placed in arguments, logs, or preferences.
- [ ] Archive writes still go through staging and validation.
- [ ] Existing files are not overwritten by the merge.
- [ ] Documentation is updated when behavior changes.
- [ ] Security implications are described, or this change is not
      security-sensitive.

## Related issues

Closes #
