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

cert=/etc/letsencrypt/live/secure.example/fullchain.pem
key=/etc/letsencrypt/live/secure.example/privkey.pem
test_run 'Accept certificate path' reverse_proxy_validate_tls_path "$cert"
test_assert_status 'Reject relative certificate path' 1 reverse_proxy_validate_tls_path 'cert.pem'
test_assert_status 'Reject traversal certificate path' 1 reverse_proxy_validate_tls_path '/etc/../root/key.pem'
test_assert_status 'Reject injection certificate path' 1 reverse_proxy_validate_tls_path '/etc/a.pem;include /x'
test_assert_status 'Reject invalid certificate on save' 2 reverse_proxy_save_config secure.example localhost:8080 'bad path' "$key"
test_assert_status 'Reject certificate without key' 2 reverse_proxy_save_config secure.example localhost:8080 "$cert"

http_config=$(reverse_proxy_render_config plain.example localhost:8080)
test_assert_equal 'Keep HTTP-only config without 443' '0' "$(grep -c 443 <<<"$http_config")"

reverse_proxy_reload_nginx() { return 0; }
test_run 'Apply HTTPS config' reverse_proxy_apply_config secure.example localhost:8080 "$cert" "$key"
test_run 'Listen on 443' grep -q 'listen 443 ssl;' "$temporary_dir/secure.example.conf"
test_run 'Write certificate' grep -q "ssl_certificate $cert;" "$temporary_dir/secure.example.conf"
test_run 'Redirect HTTP to HTTPS' grep -q 'return 301 https://' "$temporary_dir/secure.example.conf"
test_run 'Keep ACME challenge on HTTP' grep -q 'acme-challenge' "$temporary_dir/secure.example.conf"
test_run 'Reload HTTPS configs' reverse_proxy_load_configs
test_assert_equal 'Parse HTTPS destination' 'localhost:8080' "${reverse_proxy_destinations[secure.example]}"
test_assert_equal 'Parse HTTPS certificate' "$cert"$'\t'"$key" "${reverse_proxy_tls[secure.example]}"

reverse_proxy_reload_nginx() { return 1; }
test_assert_status 'Report failed HTTPS to HTTP switch' 1 reverse_proxy_apply_config secure.example localhost:8080
test_run 'Roll back to HTTPS config' grep -q 'listen 443 ssl;' "$temporary_dir/secure.example.conf"

reverse_proxy_reload_nginx() { return 0; }
test_run 'Switch back to HTTP only' reverse_proxy_apply_config secure.example localhost:8080
test_run 'Drop 443 listener' bash -c '! grep -q 443 "$1"' _ "$temporary_dir/secure.example.conf"
test_assert_equal 'Clear TLS cache entry' '0' "${#reverse_proxy_tls[@]}"

# Automatic certificates via certbot (certbot and Nginx are stubbed).
reverse_proxy_acme_webroot="$temporary_dir/webroot"
test_run 'Accept empty email' reverse_proxy_validate_email ''
test_run 'Accept valid email' reverse_proxy_validate_email admin@example.com
test_assert_status 'Reject malformed email' 1 reverse_proxy_validate_email 'a b@example.com'
test_assert_status 'Reject option-like email' 1 reverse_proxy_validate_email '--email@x'

acme_config=$(reverse_proxy_render_config auto.example localhost:3000 '' '' acme)
test_assert_equal 'Serve ACME challenge in bootstrap config' '1' "$(grep -c 'acme-challenge' <<<"$acme_config")"
test_assert_equal 'Use configured webroot' '1' "$(grep -c "root $reverse_proxy_acme_webroot;" <<<"$acme_config")"
test_assert_equal 'Keep proxying in bootstrap config' '1' "$(grep -c 'proxy_pass http://localhost:3000;' <<<"$acme_config")"
test_assert_equal 'Skip 443 in bootstrap config' '0' "$(grep -c 443 <<<"$acme_config")"

reverse_proxy_reload_nginx() { return 0; }
unset -f certbot 2>/dev/null
if ! command -v certbot >/dev/null; then
   test_assert_status 'Report missing certbot' 1 reverse_proxy_apply_config_with_certbot auto.example localhost:3000
fi
certbot() { :; }
test_assert_status 'Reject invalid certbot email' 2 reverse_proxy_apply_config_with_certbot auto.example localhost:3000 'bad email'

certbot_log="$temporary_dir/certbot.log"
reverse_proxy_run_certbot() { printf '%s|%s\n' "$1" "$2" >>"$certbot_log"; }
test_run 'Issue certificate and apply HTTPS' reverse_proxy_apply_config_with_certbot auto.example localhost:3000 admin@example.com
test_assert_equal 'Pass domain and email to certbot' 'auto.example|admin@example.com' "$(cat "$certbot_log")"
test_run 'Create ACME webroot' test -d "$reverse_proxy_acme_webroot"
test_run 'Write Let'"'"'s Encrypt certificate' grep -q 'ssl_certificate /etc/letsencrypt/live/auto.example/fullchain.pem;' "$temporary_dir/auto.example.conf"
test_run 'Listen on 443 after issuing' grep -q 'listen 443 ssl;' "$temporary_dir/auto.example.conf"
test_assert_equal 'Cache automatic certificate' '/etc/letsencrypt/live/auto.example/fullchain.pem' "${reverse_proxy_tls[auto.example]%%$'\t'*}"

reverse_proxy_run_certbot() { return 1; }
rm -f -- "$temporary_dir/auto.example.conf"
test_assert_status 'Report failed certificate issue' 1 reverse_proxy_apply_config_with_certbot auto.example localhost:3000
test_run 'Remove config when issuing fails' test ! -e "$temporary_dir/auto.example.conf"

reverse_proxy_save_config plain2.example localhost:4000
test_assert_status 'Report failed issue for existing domain' 1 reverse_proxy_apply_config_with_certbot plain2.example localhost:4000
test_run 'Restore previous config when issuing fails' grep -q 'listen 80;' "$temporary_dir/plain2.example.conf"
test_run 'Drop bootstrap challenge on failure' bash -c '! grep -q acme-challenge "$1"' _ "$temporary_dir/plain2.example.conf"

test_finish
