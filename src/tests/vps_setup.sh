#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../core/vps_setup.sh
source "$test_dir/../core/vps_setup.sh"
unset test_dir

test_run 'Accept valid SSH port' vps_setup_validate_ssh_port 2222
test_assert_status 'Reject SSH port zero' 1 vps_setup_validate_ssh_port 0
test_assert_status 'Reject SSH port above range' 1 vps_setup_validate_ssh_port 65536
test_run 'Accept SSH config handle' vps_setup_validate_ssh_handle production-vps_1
test_assert_status 'Reject unsafe SSH config handle' 1 vps_setup_validate_ssh_handle 'bad handle'
test_run 'Accept ED25519 public key' vps_setup_validate_public_key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGpvc2VwaGluZUtleS1NYXRlcmlhbA== test@example'
test_assert_status 'Reject multiline public key' 1 vps_setup_validate_public_key $'ssh-ed25519 key\nnext'

missing_config=$(mktemp -u)
VPS_SETUP_SSHD_CONFIG="$missing_config"
test_assert_equal 'Default SSH port without config' '22' "$(vps_setup_ssh_port)"
unset VPS_SETUP_SSHD_CONFIG

privileged_commands=()
vps_setup_run_privileged() {
	privileged_commands+=("$*")
}
test_run 'Update packages with privileges' vps_setup_update_packages
test_assert_equal 'Run package update with privileges' 'apt-get update' "${privileged_commands[0]}"
test_assert_equal 'Run package upgrade with privileges' 'apt-get upgrade -y' "${privileged_commands[1]}"

privileged_commands=()
test_run 'Install Nginx with privileges' vps_setup_install_software nginx
test_assert_equal 'Run package install with privileges' 'apt-get install -y -- nginx' "${privileged_commands[0]}"

mongodb_directory=$(mktemp -d)
VPS_SETUP_OS_RELEASE="$mongodb_directory/os-release"
VPS_SETUP_CPUINFO="$mongodb_directory/cpuinfo"
VPS_SETUP_APT_KEYRING_DIR="$mongodb_directory/keyrings"
VPS_SETUP_APT_SOURCES_DIR="$mongodb_directory/sources.list.d"
mongodb_keyring="$VPS_SETUP_APT_KEYRING_DIR/mongodb-server-9.gpg"
mongodb_sources_list="$VPS_SETUP_APT_SOURCES_DIR/mongodb-org-9.0.list"
mongodb_architecture=amd64
fail_apt_update=''
printf 'ID=ubuntu
VERSION_CODENAME="noble"
' >"$VPS_SETUP_OS_RELEASE"
printf 'flags		: fpu sse2 avx avx2
' >"$VPS_SETUP_CPUINFO"

vps_setup_run_privileged() {
	privileged_commands+=("$*")
	case "$1" in
	install | rm) "$@" ;;
	apt-get) [[ "$*" != 'apt-get update' || -z "$fail_apt_update" ]] ;;
	esac
}
vps_setup_architecture() {
	printf '%s' "$mongodb_architecture"
}
vps_setup_download_key() {
	printf 'mongodb key
' >"$2"
}
privileged_command_index() {
	local index

	for index in "${!privileged_commands[@]}"; do
		[[ "${privileged_commands[index]}" == "$1" ]] && printf '%s' "$index" && return 0
	done
	printf 'missing'
	return 1
}

test_assert_equal 'Read quoted os-release value' 'noble' "$(vps_setup_os_release_value VERSION_CODENAME)"
test_assert_equal 'Render MongoDB Ubuntu repository' 	'deb [ arch=amd64 signed-by=/k.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/9.0 multiverse' 	"$(vps_setup_mongodb_repo_line ubuntu noble amd64 /k.gpg 9.0)"
test_assert_equal 'Render MongoDB Debian repository' 	'deb [ arch=arm64 signed-by=/k.gpg ] https://repo.mongodb.org/apt/debian trixie/mongodb-org/9.0 main' 	"$(vps_setup_mongodb_repo_line debian trixie arm64 /k.gpg 9.0)"
test_assert_status 'Reject MongoDB repository for other distro' 2 vps_setup_mongodb_repo_line fedora 40 amd64 /k.gpg 9.0
test_assert_status 'Reject unsafe MongoDB codename' 2 vps_setup_mongodb_repo_line ubuntu 'noble main' amd64 /k.gpg 9.0

privileged_commands=()
test_assert_status 'Install MongoDB on Ubuntu' 0 vps_setup_install_software mongodb
test_assert_equal 'Install MongoDB prerequisites first' 'apt-get install -y -- ca-certificates curl gnupg' "${privileged_commands[0]}"
test_assert_equal 'Write MongoDB repository' 	"deb [ arch=amd64 signed-by=$mongodb_keyring ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/9.0 multiverse" 	"$(<"$mongodb_sources_list")"
test_assert_equal 'Write MongoDB signing key' 'mongodb key' "$(<"$mongodb_keyring")"
update_index=$(privileged_command_index 'apt-get update')
install_index=$(privileged_command_index 'apt-get install -y -- mongodb-org')
test_run 'Install MongoDB after repository update' test "$update_index" -lt "$install_index"
test_assert_equal 'Skip MongoDB removal without reinstall' 'missing' "$(privileged_command_index "apt-get remove -y -- mongodb-org mongodb-org-database mongodb-org-server mongodb-org-mongos mongodb-org-tools mongodb-org-database-tools-extra mongodb-mongosh mongodb-database-tools")"

privileged_commands=()
test_assert_status 'Reinstall MongoDB' 0 vps_setup_install_software mongodb 1
remove_index=$(privileged_command_index "apt-get remove -y -- mongodb-org mongodb-org-database mongodb-org-server mongodb-org-mongos mongodb-org-tools mongodb-org-database-tools-extra mongodb-mongosh mongodb-database-tools")
install_index=$(privileged_command_index 'apt-get install -y -- mongodb-org')
test_run 'Remove all MongoDB packages before reinstall' test "$remove_index" -lt "$install_index"

printf 'deb previous
' >"$mongodb_sources_list"
fail_apt_update=1
privileged_commands=()
test_assert_status 'Fail MongoDB install when APT update fails' 1 vps_setup_install_mongodb
test_assert_equal 'Restore previous MongoDB repository' 'deb previous' "$(<"$mongodb_sources_list")"
test_assert_equal 'Skip MongoDB packages after update failure' 'missing' "$(privileged_command_index 'apt-get install -y -- mongodb-org')"

rm -f -- "$mongodb_sources_list" "$mongodb_keyring"
test_assert_status 'Fail fresh MongoDB repository setup' 1 vps_setup_install_mongodb
test_run 'Remove new MongoDB repository after failure' test ! -e "$mongodb_sources_list"
test_run 'Remove new MongoDB key after failure' test ! -e "$mongodb_keyring"
fail_apt_update=''

vps_setup_download_key() {
	return 1
}
test_assert_status 'Fail MongoDB install when key download fails' 1 vps_setup_install_mongodb
test_run 'Write no MongoDB repository without key' test ! -e "$mongodb_sources_list"
test_run 'Write no MongoDB key after download failure' test ! -e "$mongodb_keyring"
vps_setup_download_key() {
	printf 'mongodb key\n' >"$2"
}

printf 'flags		: fpu sse2
' >"$VPS_SETUP_CPUINFO"
privileged_commands=()
test_assert_status 'Reject MongoDB on amd64 without AVX' 2 vps_setup_install_mongodb
test_assert_equal 'Change nothing without AVX' 0 "${#privileged_commands[@]}"
mongodb_architecture=arm64
test_assert_status 'Allow MongoDB on arm64 without AVX check' 0 vps_setup_install_mongodb
mongodb_architecture=armhf
test_assert_status 'Reject MongoDB on unsupported architecture' 2 vps_setup_install_mongodb
mongodb_architecture=amd64

printf 'ID=fedora
VERSION_CODENAME=
' >"$VPS_SETUP_OS_RELEASE"
privileged_commands=()
test_assert_status 'Reject MongoDB on non-Debian distro' 2 vps_setup_install_mongodb
test_assert_equal 'Change nothing on non-Debian distro' 0 "${#privileged_commands[@]}"
rm -rf -- "$mongodb_directory"
unset VPS_SETUP_OS_RELEASE VPS_SETUP_CPUINFO VPS_SETUP_APT_KEYRING_DIR VPS_SETUP_APT_SOURCES_DIR

test_finish