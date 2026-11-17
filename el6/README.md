# EL6 Build Tree (`el6/`)

RPM spec for backporting OpenSSH on Enterprise Linux 6 (SysVinit).

## Notes

- System Perl (>= 5.10) is sufficient, so unlike `el5/` no Perl
  bootstrap is needed.
- OpenSSL is built statically and linked into the OpenSSH binaries
  (`WITH_OPENSSL=2`); system OpenSSL stays untouched.

Versions come from `version.env`. For usage and supported distros see
the root [README.md](../README.md).
