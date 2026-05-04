
echo "=== posix_quote() ==="

assert_eq "plain path" "'/tmp/project'" "$(posix_quote "/tmp/project")"
assert_eq "path with space" "'/tmp/my project'" "$(posix_quote "/tmp/my project")"
assert_eq "path with single quote" "'/tmp/project'\"'\"'s dir'" "$(posix_quote "/tmp/project's dir")"
assert_eq "path with double quote" "'/tmp/project\"dir'" "$(posix_quote '/tmp/project"dir')"
assert_eq "empty string" "''" "$(posix_quote "")"

eval_result=$(eval "echo $(posix_quote "/tmp/project's dir")")
assert_eq "round-trips through eval" "/tmp/project's dir" "$eval_result"
