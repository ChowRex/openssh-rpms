# EL7+ Build Tree (`el7/`)

RPM spec for backporting OpenSSH on Enterprise Linux 7 and newer
(EL7/EL8/EL9 incl. RHEL, CentOS, Rocky, AlmaLinux) using native systemd
services.

## Notes

- Installs systemd units into `%{_unitdir}`: `sshd.service`,
  `sshd.socket` (socket activation), `sshd@.service`, and
  `sshd-keygen.service`.
- Two specs available: `openssh.spec` (default, systemd) and
  `openssh.initv.spec` (SysVinit), selected via the `SPECFILE` env var.
- OpenSSL mode: system OpenSSL >= 3 is used directly
  (`WITH_OPENSSL=1`), otherwise OpenSSL is built statically
  (`WITH_OPENSSL=2`). Override via env, see `version.env`.

After installing the RPMs:

```bash
systemctl enable --now sshd
```

Versions come from `version.env`. For usage and supported distros see
the root [README.md](../README.md).
