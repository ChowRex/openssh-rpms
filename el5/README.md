# EL5 Build Tree (`el5/`)

RPM spec for backporting OpenSSH on Enterprise Linux 5 (SysVinit).

## Notes

- **Perl bootstrap**: modern OpenSSL requires Perl >= 5.10, while EL5
  ships Perl 5.8. If the system Perl is too old, a private Perl
  (`PERLSRC` in `version.env`) is built inside the build tree and used
  only to compile OpenSSL; it is neither packaged nor installed.
  `compile.sh` adds `PERLSRC` to the source list automatically for this
  directory.
- **Toolchain**: built with `CC=gcc44`; OpenSSL is linked statically
  (`WITH_OPENSSL=2`).

Versions come from `version.env`. For usage, config variables, and
supported distros see the root [README.md](../README.md).
