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

test_finish