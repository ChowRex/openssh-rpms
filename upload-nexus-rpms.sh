#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_STAGE_DIR="$SCRIPT_DIR/nexus-upload/v10.6p2_b1"
NEXUS_BASE_URL="${NEXUS_BASE_URL:-https://nexus.goldwind.com/repository/gw-yum-hosted}"
NETRC_FILE="${NETRC_FILE:-$SCRIPT_DIR/nexus.netrc}"
REQUEST_DELAY_SECONDS="${REQUEST_DELAY_SECONDS:-1}"
METADATA_WAIT_SECONDS="${METADATA_WAIT_SECONDS:-70}"

usage() {
	cat <<EOF
Usage:
  $0 [--dry-run | --upload] [staging-directory]

Arguments:
  --dry-run  List each local RPM and its Nexus destination. This is the default
              and makes no network requests or remote changes.
  --upload   Check that every remote RPM path is unused, request an explicit
              confirmation, then upload the complete staging directory.

Environment:
  NETRC_FILE=<path>              Defaults to ./nexus.netrc
  NEXUS_BASE_URL=<URL>           Defaults to the gw-yum-hosted repository URL
  REQUEST_DELAY_SECONDS=<number> Defaults to 1; serializes Nexus requests
  METADATA_WAIT_SECONDS=<number> Defaults to 70 before metadata validation
EOF
}

mode=dry-run
case "${1:-}" in
	--dry-run)
		shift
		;;
	--upload)
		mode=upload
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
esac

if [[ $# -gt 1 ]]; then
	usage >&2
	exit 2
fi

stage_dir=${1:-"$DEFAULT_STAGE_DIR"}
if [[ ! -d $stage_dir ]]; then
	echo "Staging directory not found: $stage_dir" >&2
	exit 1
fi
stage_dir=$(cd "$stage_dir" && pwd)

if [[ ! -f $NETRC_FILE ]]; then
	echo "Nexus credentials file not found: $NETRC_FILE" >&2
	exit 1
fi

files_file=$(mktemp)
roots_file=$(mktemp)
trap 'rm -f "$files_file" "$roots_file" "${roots_file}.sorted"' EXIT

find "$stage_dir" -type f -name '*.rpm' -print | LC_ALL=C sort >"$files_file"
if [[ ! -s $files_file ]]; then
	echo "No RPM files found under: $stage_dir" >&2
	exit 1
fi

validate_relative_path() {
	local relative_path="$1"
	local family release arch filename extra

	IFS=/ read -r family release arch filename extra <<EOF
$relative_path
EOF
	if [[ -z $family || -z $release || -z $arch || -z $filename || -n ${extra:-} ]]; then
		echo "Expected exactly family/release/arch/file.rpm: $relative_path" >&2
		return 1
	fi
	if [[ ! $family =~ ^[[:alnum:]._-]+$ || ! $release =~ ^[[:alnum:]._-]+$ || ! $arch =~ ^[[:alnum:]._-]+$ || ! $filename =~ ^[[:alnum:]._-]+\.rpm$ ]]; then
		echo "Unsafe Nexus path component: $relative_path" >&2
		return 1
	fi
}

print_mapping() {
	local file="$1"
	local relative_path remote_url

	relative_path=${file#"$stage_dir/"}
	validate_relative_path "$relative_path"
	remote_url="$NEXUS_BASE_URL/$relative_path"
	printf '%s\n  -> %s\n' "$relative_path" "$remote_url"
}

rpm_count=$(wc -l <"$files_file" | tr -d '[:space:]')
printf 'Staging directory: %s\n' "$stage_dir"
printf 'RPM files: %s\n' "$rpm_count"
printf 'Nexus repository: %s\n\n' "$NEXUS_BASE_URL"

while IFS= read -r file; do
	print_mapping "$file"
done <"$files_file"

if [[ $mode == dry-run ]]; then
	printf '\nDry run complete. No Nexus request was made.\n'
	exit 0
fi

printf '\nPreflight: verify that every destination path is unused.\n'
while IFS= read -r file; do
	relative_path=${file#"$stage_dir/"}
	validate_relative_path "$relative_path"
	remote_url="$NEXUS_BASE_URL/$relative_path"
	http_code=$(curl --netrc-file "$NETRC_FILE" \
		--range 0-0 \
		--connect-timeout 15 \
		--max-time 45 \
		--silent --show-error \
		--output /dev/null \
		--write-out '%{http_code}' \
		"$remote_url")
	case $http_code in
		404)
			;;
		200 | 206)
			echo "Refusing to overwrite existing Nexus asset: $remote_url" >&2
			exit 1
			;;
		*)
			echo "Unable to verify Nexus destination (HTTP $http_code): $remote_url" >&2
			exit 1
			;;
	esac
	sleep "$REQUEST_DELAY_SECONDS"
done <"$files_file"

printf '\nAll destination paths are unused.\n'
printf 'Type UPLOAD to publish %s RPM files: ' "$rpm_count"
read -r confirmation
if [[ $confirmation != UPLOAD ]]; then
	echo 'Upload cancelled. No RPM was uploaded.'
	exit 0
fi

printf '\nUploading RPMs serially.\n'
while IFS= read -r file; do
	relative_path=${file#"$stage_dir/"}
	remote_url="$NEXUS_BASE_URL/$relative_path"
	http_code=$(curl --netrc-file "$NETRC_FILE" \
		--upload-file "$file" \
		--connect-timeout 15 \
		--max-time 300 \
		--silent --show-error \
		--output /dev/null \
		--write-out '%{http_code}' \
		"$remote_url")
	case $http_code in
		200 | 201 | 204)
			printf 'Uploaded: %s\n' "$relative_path"
			;;
		*)
			echo "Upload failed (HTTP $http_code): $remote_url" >&2
			exit 1
			;;
	esac
	printf '%s\n' "$(dirname "$relative_path")" >>"$roots_file"
	sleep "$REQUEST_DELAY_SECONDS"
done <"$files_file"

LC_ALL=C sort -u "$roots_file" >"${roots_file}.sorted"
printf '\nWaiting %s seconds for Nexus Yum metadata generation.\n' "$METADATA_WAIT_SECONDS"
sleep "$METADATA_WAIT_SECONDS"

printf '\nVerifying repodata/repomd.xml for every uploaded Yum root.\n'
while IFS= read -r root; do
	metadata_url="$NEXUS_BASE_URL/$root/repodata/repomd.xml"
	http_code=$(curl --netrc-file "$NETRC_FILE" \
		--range 0-0 \
		--connect-timeout 15 \
		--max-time 45 \
		--silent --show-error \
		--output /dev/null \
		--write-out '%{http_code}' \
		"$metadata_url")
	case $http_code in
		200 | 206)
			printf 'Metadata available: %s\n' "$root"
			;;
		*)
			echo "Metadata verification failed (HTTP $http_code): $metadata_url" >&2
			exit 1
			;;
	esac
	sleep "$REQUEST_DELAY_SECONDS"
done <"${roots_file}.sorted"

printf '\nUpload and Yum metadata verification completed successfully.\n'
