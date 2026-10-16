#!/usr/bin/env bash

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/test.sh
source "$test_dir/../lib/test.sh"
# shellcheck source=../lib/settings.sh
source "$test_dir/../lib/settings.sh"
# shellcheck source=../core/reverse_proxy.sh
source "$test_dir/../core/reverse_proxy.sh"
unset test_dir

temporary_dir=$(mktemp -d)
trap 'rm -rf -- "$temporary_dir"' EXIT
settings[NGINX_CONFIG_DIR]="$temporary_dir"

settings[NGINX_CONFIG_DIR]="$temporary_dir/missing/conf.d"
test_run 'Create missing config directory' reverse_proxy_ensure_config_directory
test_run 'Create configured directory path' test -d "${settings[NGINX_CONFIG_DIR]}"
settings[NGINX_CONFIG_DIR]="$temporary_dir"

test_run 'Accept valid domain' reverse_proxy_validate_domain example.com
test_assert_status 'Reject empty domain' 1 reverse_proxy_validate_domain ''
test_assert_status 'Reject path traversal domain' 1 reverse_proxy_validate_domain '../example.com'
test_run 'Accept maximum port' reverse_proxy_validate_port 65535
test_assert_status 'Reject out-of-range port' 1 reverse_proxy_validate_port 65536
test_assert_status 'Reject oversized numeric port' 1 reverse_proxy_validate_port 999999999999999999999999
test_run 'Accept host and port destination' reverse_proxy_validate_destination 10.0.0.5:8080
test_run 'Accept domain destination without port' reverse_proxy_validate_destination backend.example.com
test_run 'Accept IPv6 destination' reverse_proxy_validate_destination '[::1]:3000'
test_assert_status 'Reject destination with bad port' 1 reverse_proxy_validate_destination host:99999
test_assert_status 'Reject destination injection' 1 reverse_proxy_validate_destination 'host;return'
test_assert_status 'Reject bracketed non-IPv6' 1 reverse_proxy_validate_destination '[host]'
test_assert_status 'Reject config injection domain' 2 reverse_proxy_save_config 'example.com;return' 80

test_run 'Save reverse proxy config' reverse_proxy_save_config example.com localhost:8080
test_run 'Write expected upstream' grep -q 'proxy_pass http://localhost:8080;' "$temporary_dir/example.com.conf"
test_run 'Load reverse proxy configs' reverse_proxy_load_configs
test_assert_equal 'Parse domain and destination' 'localhost:8080' "${reverse_proxy_destinations[example.com]}"

printf 'server_name ;\nproxy_pass http://localhost:8081;\n' >"$temporary_dir/invalid.conf"
test_assert_status 'Ignore config with empty domain' 1 reverse_proxy_load_configs
test_assert_equal 'Keep only valid cached domain' '1' "${#reverse_proxy_destinations[@]}"
rm -f -- "$temporary_dir/invalid.conf"

rm -f -- "$temporary_dir/example.com.conf"
test_run 'Reload empty config directory' reverse_proxy_load_configs
test_assert_equal 'Clear stale cache entries' '0' "${#reverse_proxy_destinations[@]}"

reverse_proxy_reload_nginx() { return 0; }
test_run 'Apply config after successful reload' reverse_proxy_apply_config example.com backend.internal:80
test_run 'Cache applied config' test "${reverse_proxy_destinations[example.com]}" = backend.internal:80

reverse_proxy_reload_nginx() { return 1; }
test_assert_status 'Report failed Nginx reload' 1 reverse_proxy_apply_config example.com backend.internal:81
test_run 'Roll back failed modification' grep -q 'proxy_pass http://backend.internal:80;' "$temporary_dir/example.com.conf"
test_assert_status 'Report failed delete reload' 1 reverse_proxy_remove_config example.com
test_run 'Roll back failed deletion' test -f "$temporary_dir/example.com.conf"

reverse_proxy_reload_nginx() { return 0; }
test_run 'Delete config after successful reload' reverse_proxy_remove_config example.com
test_run 'Remove deleted file' test ! -e "$temporary_dir/example.com.conf"
test_assert_equal 'Remove deleted cache entry' '0' "${#reverse_proxy_destinations[@]}"

test_finish
